#!/usr/bin/env fish

# =========================================================
# CONFIGURAÇÕES
# =========================================================
set SSH_HOST_ALIAS rifashow-backup
set REMOTE_USER root
set REMOTE_HOST 45.56.112.138
set REMOTE_PORT 6969

set SSH_KEY_PATH "$HOME/.ssh/id_ed25519_rifashow_backup"

set REMOTE_MONGO_URI 'mongodb://cledson:Beta0411!@127.0.0.1/rifashow?directConnection=true&authSource=admin'
set DB_NAME rifashow

set DATE (date +%Y-%m-%d)
set DUMP_DIR "rifashow-$DATE"
set TAR_FILE "$DUMP_DIR.tar.gz"

set REMOTE_BASE_PATH "/root"
set LOCAL_BASE_PATH "$HOME/Downloads"

# =========================================================
# GARANTIR PASTA LOCAL
# =========================================================
if not test -d $LOCAL_BASE_PATH
    mkdir -p $LOCAL_BASE_PATH
end

# =========================================================
# GARANTIR DIRETÓRIO SSH
# =========================================================
if not test -d ~/.ssh
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
end

# =========================================================
# GERAR CHAVE DEDICADA (SE NECESSÁRIO)
# =========================================================
if not test -f $SSH_KEY_PATH
    echo "🔑 Gerando chave SSH dedicada..."
    ssh-keygen -t ed25519 -f $SSH_KEY_PATH
end

# =========================================================
# GARANTIR CONFIG NO ~/.ssh/config
# =========================================================
set SSH_CONFIG "$HOME/.ssh/config"

if not test -f $SSH_CONFIG
    touch $SSH_CONFIG
    chmod 600 $SSH_CONFIG
end

if not grep -q "Host $SSH_HOST_ALIAS" $SSH_CONFIG
    echo "🧾 Adicionando host SSH '$SSH_HOST_ALIAS' ao config..."
    printf "\nHost %s\n  HostName %s\n  User %s\n  Port %s\n  IdentityFile %s\n  IdentitiesOnly yes\n" \
        $SSH_HOST_ALIAS $REMOTE_HOST $REMOTE_USER $REMOTE_PORT $SSH_KEY_PATH >> $SSH_CONFIG
end

# =========================================================
# VERIFICAR / CONFIGURAR AUTENTICAÇÃO
# =========================================================
echo "🔐 Verificando autenticação SSH por chave..."

ssh -o BatchMode=yes $SSH_HOST_ALIAS "echo ok" >/dev/null 2>&1
set SSH_OK $status

if test $SSH_OK -ne 0
    echo "📤 Copiando chave para o servidor (senha será solicitada UMA vez)..."
    ssh-copy-id -i "$SSH_KEY_PATH.pub" $SSH_HOST_ALIAS

    ssh -o BatchMode=yes $SSH_HOST_ALIAS "echo ok" >/dev/null 2>&1
    or begin
        echo "❌ Falha ao configurar SSH por chave. Abortando."
        exit 1
    end
end

echo "✅ SSH por chave pronto."

# =========================================================
# DUMP + COMPACTAÇÃO REMOTA
# =========================================================
echo "➡️ Gerando dump no servidor remoto..."

ssh $SSH_HOST_ALIAS "bash -c '
  set -e
  cd $REMOTE_BASE_PATH
  mongodump --uri=\"$REMOTE_MONGO_URI\" --db $DB_NAME -v -o ./$DUMP_DIR
  echo \"📦 Compactando dump...\"
  tar -czvf $TAR_FILE $DUMP_DIR
'"

# =========================================================
# DOWNLOAD
# =========================================================
echo "⬇️ Baixando dump..."
scp $SSH_HOST_ALIAS:$REMOTE_BASE_PATH/$TAR_FILE $LOCAL_BASE_PATH/

# =========================================================
# LIMPEZA REMOTA
# =========================================================
read -P "🧹 Remover dump do servidor remoto? (y/N) " REMOVE_REMOTE
if test "$REMOVE_REMOTE" = "y"
    ssh $SSH_HOST_ALIAS "rm -rf $REMOTE_BASE_PATH/$DUMP_DIR $REMOTE_BASE_PATH/$TAR_FILE"
end

# =========================================================
# DESCOMPACTAR LOCAL
# =========================================================
echo "📦 Descompactando dump localmente..."
cd $LOCAL_BASE_PATH
tar -xzvf $TAR_FILE

# =========================================================
# RESTORE LOCAL
# =========================================================
read -P "♻️ Restaurar dump localmente? (y/N) " RESTORE_LOCAL
if test "$RESTORE_LOCAL" = "y"
    mongorestore --drop --uri="mongodb://localhost:27017" $DUMP_DIR
end

# =========================================================
# LIMPEZA LOCAL
# =========================================================
read -P "🧹 Remover dump local? (y/N) " REMOVE_LOCAL
if test "$REMOVE_LOCAL" = "y"
    rm -rf $DUMP_DIR $TAR_FILE
end

echo "✅ Backup finalizado com sucesso."

