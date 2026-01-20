#!/usr/bin/env fish

# Lista todos os kernels instalados, ordenando do mais recente para o mais antigo
set kernels (dpkg --list | grep '^ii' | grep linux-image- | awk '{print $2}' | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+-[0-9]+' | sort -Vr)

if test (count $kernels) -eq 0
    echo "Nenhum kernel instalado encontrado."
    exit 1
end

echo "=== Kernels instalados ==="
for i in (seq (count $kernels))
    echo "$i) $kernels[$i]"
end

# Pergunta qual kernel o usuário deseja reinstalar
echo
read -P "Digite o número do kernel que deseja reinstalar: " choice

if not string match -rq '^[0-9]+$' -- $choice
    echo "Entrada inválida. Saindo..."
    exit 1
end

if test $choice -lt 1 -o $choice -gt (count $kernels)
    echo "Número fora do intervalo. Saindo..."
    exit 1
end

# Usamos outro nome de variável (não 'version', que é reservada no fish)
set kernel_ver $kernels[$choice]

echo
echo "=== Reinstalando kernel $kernel_ver... ==="
sudo apt reinstall -y linux-image-$kernel_ver-generic linux-headers-$kernel_ver-generic

if test $status -ne 0
    echo "❌ Erro ao reinstalar o kernel."
    exit 1
end

echo
echo "=== Atualizando initramfs ==="
sudo update-initramfs -u -k $kernel_ver-generic

echo
echo "=== Atualizando GRUB ==="
sudo update-grub

echo
echo "✅ Kernel $kernel_ver reinstalado e configurado com sucesso!"
echo "Reinicie o sistema para aplicar:"
echo "  sudo reboot"
