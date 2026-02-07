#!/usr/bin/env fish

echo "String de conexão:"
echo "mongodb://cledson:Beta0411!@127.0.0.1:27018/rifashow?directConnection=true&authSource=admin"
echo ""
echo "Iniciando túnel SSH..."

# Inicia o túnel em background
ssh -N -L 27018:127.0.0.1:27017 -p 6969 -o ServerAliveInterval=60 -o ServerAliveCountMax=3 root@45.56.112.138 &
set ssh_pid $last_pid

# Aguarda a porta ficar disponível
sleep 2
if lsof -i :27018 -sTCP:LISTEN -t >/dev/null 2>&1
    echo "✓ Túnel SSH estabelecido com sucesso! (PID: $ssh_pid)"
    echo "  Pressione Ctrl+C para encerrar"
else
    echo "✗ Erro ao estabelecer o túnel SSH"
    kill $ssh_pid 2>/dev/null
    exit 1
end

# Aguarda o processo SSH
wait $ssh_pid

