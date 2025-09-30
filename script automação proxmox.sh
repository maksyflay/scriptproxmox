#!/bin/bash
# Script para automatizar criação de VM e CT no Proxmox
# Autor: Maksyflay Souza 🚀

STORAGE_LOCAL="local"
IMAGES_DIR="/var/lib/vz/template/iso"
TEMPLATE_DIR="/var/lib/vz/template/cache"

# Detecta storage válido para rootfs/discos
detect_storage() {
    DISK_STORAGE=$(pvesm status --content rootdir,images | awk 'NR>1 {print $1; exit}')
    if [ -z "$DISK_STORAGE" ]; then
        DISK_STORAGE="local-lvm"  # fallback
    fi
    echo "$DISK_STORAGE"
}

# ---------------------- FUNÇÕES ----------------------

listar_isos() {
    echo "📀 ISOs disponíveis:"
    ISOS=($(ls -1 ${IMAGES_DIR}/*.iso 2>/dev/null | sed "s|${IMAGES_DIR}/||"))
    if [ ${#ISOS[@]} -eq 0 ]; then
        echo "Nenhuma ISO local encontrada."
    else
        for i in "${!ISOS[@]}"; do
            echo "$((i+1))) ${ISOS[$i]}"
        done
    fi
    LOCAL_COUNT=${#ISOS[@]}
    echo "$((LOCAL_COUNT+1))) Baixar nova ISO (URL manual)"
    echo "$((LOCAL_COUNT+2))) Baixar ISO oficial (lista pveam)"
}

listar_templates() {
    echo "📦 Templates LXC disponíveis:"
    TEMPLATES=($(ls -1 ${TEMPLATE_DIR}/*.tar.* 2>/dev/null | sed "s|${TEMPLATE_DIR}/||"))
    if [ ${#TEMPLATES[@]} -eq 0 ]; then
        echo "Nenhum template local encontrado."
    else
        for i in "${!TEMPLATES[@]}"; do
            echo "$((i+1))) ${TEMPLATES[$i]}"
        done
    fi
    LOCAL_COUNT=${#TEMPLATES[@]}
    echo "$((LOCAL_COUNT+1))) Baixar novo template (lista oficial pveam)"
}

baixar_iso_url() {
    echo "Digite a URL da ISO para baixar:"
    read ISO_URL
    wget -P "${IMAGES_DIR}" "$ISO_URL"
}

baixar_iso_oficial() {
    echo "🔍 Buscando ISOs oficiais do Proxmox..."
    OFFICIAL=($(pveam available --section iso | awk '{print $2}'))
    for i in "${!OFFICIAL[@]}"; do
        echo "$((i+1))) ${OFFICIAL[$i]}"
    done
    read -p "Escolha o número da ISO oficial para baixar: " INUM
    ISO_ESCOLHA=${OFFICIAL[$((INUM-1))]}
    echo "⬇️ Baixando $ISO_ESCOLHA ..."
    pveam download ${STORAGE_LOCAL} "$ISO_ESCOLHA"
}

baixar_template_oficial() {
    echo "🔍 Buscando templates oficiais do Proxmox..."
    OFFICIAL=($(pveam available --section system | awk '{print $2}'))
    for i in "${!OFFICIAL[@]}"; do
        echo "$((i+1))) ${OFFICIAL[$i]}"
    done
    read -p "Escolha o número do template oficial para baixar: " TNUM
    TEMPLATE_ESCOLHA=${OFFICIAL[$((TNUM-1))]}
    echo "⬇️ Baixando $TEMPLATE_ESCOLHA ..."
    pveam download ${STORAGE_LOCAL} "$TEMPLATE_ESCOLHA"
}

# ---------------------- MENU PRINCIPAL ----------------------

echo "=== Criar VM ou Container no Proxmox ==="
echo "1) Criar VM"
echo "2) Criar Container"
read -p "Escolha uma opção: " OPCAO

DISK_STORAGE=$(detect_storage)

# ---------------------- CRIAR VM ----------------------
if [ "$OPCAO" == "1" ]; then
    echo "=== Criando VM ==="
    listar_isos
    read -p "Escolha a ISO pelo número: " ISO_NUM

    if [ "$ISO_NUM" -eq "$(( ${#ISOS[@]}+1 ))" ]; then
        baixar_iso_url
        listar_isos
        read -p "Escolha novamente a ISO pelo número: " ISO_NUM
    elif [ "$ISO_NUM" -eq "$(( ${#ISOS[@]}+2 ))" ]; then
        baixar_iso_oficial
        listar_isos
        read -p "Escolha novamente a ISO pelo número: " ISO_NUM
    fi

    ISOS=($(ls -1 ${IMAGES_DIR}/*.iso 2>/dev/null | sed "s|${IMAGES_DIR}/||"))
    ISO_ESCOLHIDO=${ISOS[$((ISO_NUM-1))]}

    if [ -z "$ISO_ESCOLHIDO" ]; then
        echo "❌ Erro: Nenhuma ISO válida selecionada."
        exit 1
    fi

    read -p "Digite o ID da VM (ex: 101): " VMID
    read -p "Digite o nome da VM: " VMNAME
    read -p "Digite o tamanho do disco em GB (ex: 20): " DISK
    read -p "Digite a quantidade de memória em MB (ex: 2048): " RAM
    read -p "Digite a quantidade de CPUs: " CPU

    qm create $VMID --name $VMNAME --memory $RAM --cores $CPU \
        --net0 virtio,bridge=vmbr0 \
        --ide2 ${STORAGE_LOCAL}:iso/${ISO_ESCOLHIDO},media=cdrom --boot order=ide2 \
        --scsihw virtio-scsi-pci --scsi0 ${DISK_STORAGE}:${DISK} --bios seabios

    # Desabilita KVM na VM
    qm set $VMID --kvm 0

    if [ $? -eq 0 ]; then
        qm start $VMID
        echo "✅ VM $VMNAME (ID: $VMID) criada, KVM desabilitado (BIOS SeaBIOS) e iniciada."
        echo "⚠️ Lembre-se: o SO instalado na VM deve estar configurado para usar DHCP."
    else
        echo "❌ Erro ao criar a VM."
    fi
fi

# ---------------------- CRIAR CONTAINER ----------------------
if [ "$OPCAO" == "2" ]; then
    echo "=== Criando Container ==="
    listar_templates
    read -p "Escolha o template pelo número: " TEMPLATE_NUM

    if [ "$TEMPLATE_NUM" -eq "$(( ${#TEMPLATES[@]}+1 ))" ]; then
        baixar_template_oficial
        listar_templates
        read -p "Escolha novamente o template pelo número: " TEMPLATE_NUM
    fi

    TEMPLATES=($(ls -1 ${TEMPLATE_DIR}/*.tar.* 2>/dev/null | sed "s|${TEMPLATE_DIR}/||"))
    TEMPLATE_ESCOLHIDO=${TEMPLATES[$((TEMPLATE_NUM-1))]}

    if [ -z "$TEMPLATE_ESCOLHIDO" ]; then
        echo "❌ Erro: Nenhum template válido selecionado."
        exit 1
    fi

    read -p "Digite o ID do CT (ex: 201): " CTID
    read -p "Digite o hostname do CT: " CTNAME
    read -sp "Digite a senha root do CT: " CTPASS
    echo ""
    read -p "Digite o tamanho do disco em GB (ex: 8): " DISK
    read -p "Digite a quantidade de memória em MB (ex: 1024): " RAM
    read -p "Digite a quantidade de CPUs: " CPU

    pct create $CTID ${STORAGE_LOCAL}:vztmpl/${TEMPLATE_ESCOLHIDO} \
        -hostname $CTNAME -password $CTPASS -rootfs ${DISK_STORAGE}:${DISK} \
        -memory $RAM -cores $CPU \
        -net0 name=eth0,bridge=vmbr0,ip=dhcp

    if [ $? -eq 0 ]; then
        pct start $CTID
        echo "✅ Container $CTNAME (ID: $CTID) criado com DHCP e iniciado com sucesso."
    else
        echo "❌ Erro ao criar o container."
    fi
fi
