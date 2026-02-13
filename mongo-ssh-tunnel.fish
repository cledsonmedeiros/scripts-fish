#!/usr/bin/env fish

echo "String de conexão:"
echo "mongodb://cledson:Beta0411!@127.0.0.1:27018/rifashow?directConnection=true&authSource=admin"
echo ""
echo "Iniciando túnel SSH..."

set existing_pid (lsof -i :27018 -sTCP:LISTEN -t 2>/dev/null)
if test -n "$existing_pid"
    echo "✗ A porta 27018 já está em uso. PID: $existing_pid"
    echo "  Feche o túnel existente e tente novamente."
    exit 1
end

set ssh_pid ""

function cleanup
    if test -n "$ssh_pid"
        if kill -0 $ssh_pid 2>/dev/null
            kill $ssh_pid 2>/dev/null
        end
    end
end

# Inicia o túnel em background
ssh -N -L 27018:127.0.0.1:27017 -p 6969 -o ServerAliveInterval=60 -o ServerAliveCountMax=3 root@45.56.112.138 &
set ssh_pid $last_pid

function on_interrupt --on-signal INT --on-signal TERM
    echo ""
    echo "Encerrando túnel SSH (PID: $ssh_pid)..."
    cleanup
    exit 0
end

# Aguarda a porta ficar disponível
sleep 2
if lsof -i :27018 -sTCP:LISTEN -t >/dev/null 2>&1
    echo "✓ Túnel SSH estabelecido com sucesso! (PID: $ssh_pid)"
    echo "  Pressione Ctrl+C para encerrar"
else
    echo "✗ Erro ao estabelecer o túnel SSH"
    cleanup
    exit 1
end

# Aguarda o processo SSH
wait $ssh_pid

