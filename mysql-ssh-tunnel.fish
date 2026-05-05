#!/usr/bin/env fish

# Tunel local para acessar o MySQL remoto via SSH.
# Variaveis opcionais:
#   MYSQL_TUNNEL_LOCAL_PORT (padrao: 33070)
#   MYSQL_REMOTE_HOST       (padrao: 127.0.0.1)
#   MYSQL_REMOTE_PORT       (padrao: 3306)
#   MYSQL_SSH_TARGET        (padrao: acoes.cc)
#   MYSQL_USER              (padrao: app)
#   MYSQL_DATABASE          (opcional)
#   MYSQL_PASSWORD          (padrao: Beta0411!)

set local_port (set -q MYSQL_TUNNEL_LOCAL_PORT; and echo $MYSQL_TUNNEL_LOCAL_PORT; or echo 33070)
set remote_host (set -q MYSQL_REMOTE_HOST; and echo $MYSQL_REMOTE_HOST; or echo 127.0.0.1)
set remote_port (set -q MYSQL_REMOTE_PORT; and echo $MYSQL_REMOTE_PORT; or echo 3306)
set ssh_target (set -q MYSQL_SSH_TARGET; and echo $MYSQL_SSH_TARGET; or echo acoes.cc)
set mysql_user (set -q MYSQL_USER; and echo $MYSQL_USER; or echo app)
set mysql_password (set -q MYSQL_PASSWORD; and echo $MYSQL_PASSWORD; or echo 'Beta0411!')

set ssh_pid ""

echo "Conexao MySQL local:"
if set -q MYSQL_DATABASE
    echo "MYSQL_PWD=*** mysql -h 127.0.0.1 -P $local_port -u $mysql_user -D $MYSQL_DATABASE"
else
    echo "MYSQL_PWD=*** mysql -h 127.0.0.1 -P $local_port -u $mysql_user"
end
echo ""
echo "Iniciando tunel SSH para MySQL..."

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
    -L $local_port:$remote_host:$remote_port \
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
