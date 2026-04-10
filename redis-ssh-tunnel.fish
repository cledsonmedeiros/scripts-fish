#!/usr/bin/env fish

# Tunel local para acessar o Redis remoto via SSH.
# Variaveis opcionais:
#   REDIS_TUNNEL_LOCAL_PORT (padrao: 63790)
#   REDIS_REMOTE_PORT       (padrao: 6379)
#   REDIS_SSH_TARGET        (padrao: acoes.cc)

set local_port (set -q REDIS_TUNNEL_LOCAL_PORT; and echo $REDIS_TUNNEL_LOCAL_PORT; or echo 63790)
set remote_port (set -q REDIS_REMOTE_PORT; and echo $REDIS_REMOTE_PORT; or echo 6379)
set ssh_target (set -q REDIS_SSH_TARGET; and echo $REDIS_SSH_TARGET; or echo acoes.cc)

set ssh_pid ""

echo "Conexao Redis local:"
if set -q REDIS_PASSWORD
    echo "redis://:$REDIS_PASSWORD@127.0.0.1:$local_port"
else
    echo "redis://127.0.0.1:$local_port"
end
echo "redis-cli -h 127.0.0.1 -p $local_port"
echo ""
echo "Iniciando tunel SSH para Redis..."

set existing_pid (lsof -i :$local_port -sTCP:LISTEN -t 2>/dev/null)
if test -n "$existing_pid"
    echo "✗ A porta $local_port ja esta em uso. PID: $existing_pid"
    echo "  Feche o processo existente e tente novamente."
    exit 1
end

function cleanup
    if test -n "$ssh_pid"; and kill -0 $ssh_pid 2>/dev/null
        kill $ssh_pid 2>/dev/null
        return
    end

    # Fallback: encerra pelo PID que estiver segurando a porta local.
    set port_pid (lsof -i :$local_port -sTCP:LISTEN -t 2>/dev/null | head -n 1)
    if test -n "$port_pid"; and kill -0 $port_pid 2>/dev/null
        kill $port_pid 2>/dev/null
    end
end

function on_interrupt --on-signal INT --on-signal TERM
    echo ""
    echo "Encerrando tunel SSH (PID: $ssh_pid)..."
    cleanup
    exit 0
end

# So vai para background depois de autenticar.
ssh -f -N \
    -L $local_port:127.0.0.1:$remote_port \
    -o ServerAliveInterval=60 \
    -o ServerAliveCountMax=3 \
    -o ExitOnForwardFailure=yes \
    $ssh_target

# Aguarda a porta ficar disponivel e identifica o PID dono do socket.
set retries 0
while test $retries -lt 10
    if lsof -i :$local_port -sTCP:LISTEN -t >/dev/null 2>&1
        set ssh_pid (lsof -i :$local_port -sTCP:LISTEN -t | head -n 1)
        break
    end
    set retries (math $retries + 1)
    sleep 1
end

if test -n "$ssh_pid"
    echo "✓ Tunel SSH estabelecido com sucesso! (PID: $ssh_pid)"
    echo "  Pressione Ctrl+C para encerrar"
else
    echo "✗ Erro ao estabelecer o tunel SSH"
    cleanup
    exit 1
end

# Mantem o script vivo enquanto o processo SSH existir.
while test -n "$ssh_pid"
    if not kill -0 $ssh_pid 2>/dev/null
        break
    end
    sleep 1
end
