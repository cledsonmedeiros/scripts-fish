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
    if test -n "$ssh_pid"; and kill -0 $ssh_pid 2>/dev/null
        kill $ssh_pid 2>/dev/null
        return
    end

    # Fallback: encerra pelo PID que estiver segurando a porta.
    set port_pid (lsof -i :27018 -sTCP:LISTEN -t 2>/dev/null | head -n 1)
    if test -n "$port_pid"; and kill -0 $port_pid 2>/dev/null
        kill $port_pid 2>/dev/null
    end
end

# Inicia o túnel e so vai para background depois de autenticar
ssh -f -N -L 27018:127.0.0.1:27017 -p 6969 -o ServerAliveInterval=60 -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes root@45.56.112.138

function on_interrupt --on-signal INT --on-signal TERM
    echo ""
    echo "Encerrando túnel SSH (PID: $ssh_pid)..."
    cleanup
    exit 0
end

# Aguarda a porta ficar disponível
sleep 2
if lsof -i :27018 -sTCP:LISTEN -t >/dev/null 2>&1
    # No macOS, $last_pid pode ficar vazio com ssh -f; pega o PID pelo socket local.
    set ssh_pid (lsof -i :27018 -sTCP:LISTEN -t | head -n 1)
    echo "✓ Túnel SSH estabelecido com sucesso! (PID: $ssh_pid)"
    echo "  Pressione Ctrl+C para encerrar"
else
    echo "✗ Erro ao estabelecer o túnel SSH"
    cleanup
    exit 1
end

# Aguarda o processo SSH (no macOS, nao e job do shell)
while test -n "$ssh_pid"
    if not kill -0 $ssh_pid 2>/dev/null
        break
    end
    sleep 1
end

