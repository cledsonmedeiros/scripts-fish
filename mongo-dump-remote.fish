#!/usr/bin/env fish

# ========================
# CONFIGURACOES PADRAO
# ========================
set SSH_HOST_ALIAS rifashow-backup
set REMOTE_USER root
set REMOTE_HOST 45.56.112.138
set REMOTE_PORT 6969
set SSH_KEY_PATH "$HOME/.ssh/id_ed25519_rifashow_backup"

set REMOTE_MONGO_URI 'mongodb://cledson:Beta0411!@127.0.0.1/rifashow?directConnection=true&authSource=admin'
set DB_NAME rifashow
set REMOTE_BASE_PATH "/root"
set LOCAL_BASE_PATH "$HOME/Downloads"
set RESTORE_URI_DEFAULT "mongodb://localhost:27017"

set DATE (date +%Y-%m-%d)
set DUMP_DIR "rifashow-$DATE"
set TAR_FILE "$DUMP_DIR.tar.gz"

function print_usage
    echo "Uso:"
    echo "  mongo-dump-remote.fish full [--yes] [--restore-uri URI]"
    echo "  mongo-dump-remote.fish dump-remote"
    echo "  mongo-dump-remote.fish restore-local [CAMINHO_DUMP_OU_TAR] [--restore-uri URI]"
    echo ""
    echo "Comandos:"
    echo "  full          Dump remoto + download + extracao + restore opcional"
    echo "  dump-remote   Apenas gera dump remoto e baixa para sua maquina"
    echo "  restore-local Apenas restaura um backup local existente"
    echo ""
    echo "Opcoes:"
    echo "  --yes, -y             Assume sim para prompts opcionais"
    echo "  --restore-uri=URI     URI de destino do mongorestore (padrao: $RESTORE_URI_DEFAULT)"
    echo ""
    echo "Exemplos:"
    echo "  mongo-dump-remote.fish dump-remote"
    echo "  mongo-dump-remote.fish restore-local ~/Downloads/rifashow-2026-03-10"
    echo "  mongo-dump-remote.fish restore-local ~/Downloads/rifashow-2026-03-10.tar.gz"
    echo "  mongo-dump-remote.fish full --yes"
end

function ensure_local_base
    if not test -d "$LOCAL_BASE_PATH"
        mkdir -p "$LOCAL_BASE_PATH"
    end
end

function ensure_ssh_ready
    if not test -d ~/.ssh
        mkdir -p ~/.ssh
        chmod 700 ~/.ssh
    end

    if not test -f "$SSH_KEY_PATH"
        echo "Gerando chave SSH dedicada..."
        ssh-keygen -t ed25519 -f "$SSH_KEY_PATH"
    end

    set SSH_CONFIG "$HOME/.ssh/config"
    if not test -f "$SSH_CONFIG"
        touch "$SSH_CONFIG"
        chmod 600 "$SSH_CONFIG"
    end

    if not grep -q "Host $SSH_HOST_ALIAS" "$SSH_CONFIG"
        echo "Adicionando host SSH '$SSH_HOST_ALIAS' ao config..."
        printf "\nHost %s\n  HostName %s\n  User %s\n  Port %s\n  IdentityFile %s\n  IdentitiesOnly yes\n" \
            "$SSH_HOST_ALIAS" "$REMOTE_HOST" "$REMOTE_USER" "$REMOTE_PORT" "$SSH_KEY_PATH" >> "$SSH_CONFIG"
    end

    echo "Verificando autenticacao SSH por chave..."
    ssh -o BatchMode=yes "$SSH_HOST_ALIAS" "echo ok" >/dev/null 2>&1
    set SSH_OK $status

    if test $SSH_OK -ne 0
        echo "Copiando chave para o servidor (senha sera solicitada UMA vez)..."
        ssh-copy-id -i "$SSH_KEY_PATH.pub" "$SSH_HOST_ALIAS"

        ssh -o BatchMode=yes "$SSH_HOST_ALIAS" "echo ok" >/dev/null 2>&1
        or begin
            echo "Falha ao configurar SSH por chave. Abortando."
            exit 1
        end
    end
end

function run_remote_dump
    echo "Gerando dump no servidor remoto..."
    ssh "$SSH_HOST_ALIAS" "set -e; cd '$REMOTE_BASE_PATH'; rm -rf '$DUMP_DIR' '$TAR_FILE'; mongodump --uri=\"$REMOTE_MONGO_URI\" --db '$DB_NAME' -o './$DUMP_DIR'; tar -czf '$TAR_FILE' '$DUMP_DIR'"
    or begin
        echo "Erro ao gerar dump remoto."
        exit 1
    end
end

function download_dump
    echo "Baixando dump para $LOCAL_BASE_PATH..."
    scp "$SSH_HOST_ALIAS:$REMOTE_BASE_PATH/$TAR_FILE" "$LOCAL_BASE_PATH/"
    or begin
        echo "Erro no download do dump."
        exit 1
    end
end

function extract_dump
    echo "Descompactando $TAR_FILE..."
    tar -xzf "$LOCAL_BASE_PATH/$TAR_FILE" -C "$LOCAL_BASE_PATH"
    or begin
        echo "Erro ao descompactar dump local."
        exit 1
    end
end

function remove_remote_artifacts
    ssh "$SSH_HOST_ALIAS" "rm -rf '$REMOTE_BASE_PATH/$DUMP_DIR' '$REMOTE_BASE_PATH/$TAR_FILE'" >/dev/null 2>&1
end

function ask_yes
    set -l question "$argv[1]"
    set -l answer ""
    read -l -P "$question (y/N) " answer
    if test "$answer" = "y" -o "$answer" = "Y"
        return 0
    end
    return 1
end

function resolve_restore_source
    set -l input_path "$argv[1]"

    if test -n "$input_path"
        if test -d "$input_path"
            echo "$input_path"
            return 0
        end

        if test -f "$input_path"
            if string match -rq '\.tar\.gz$' "$input_path"
                set -l extracted_dir (path basename "$input_path" | string replace -r '\.tar\.gz$' '')
                echo "Descompactando backup: $input_path"
                tar -xzf "$input_path" -C "$LOCAL_BASE_PATH"
                or return 1
                echo "$LOCAL_BASE_PATH/$extracted_dir"
                return 0
            end
        end

        echo "Caminho invalido para restore: $input_path"
        return 1
    end

    set -l latest_dir (ls -dt "$LOCAL_BASE_PATH"/rifashow-* 2>/dev/null | head -n 1)
    if test -n "$latest_dir"; and test -d "$latest_dir"
        echo "$latest_dir"
        return 0
    end

    echo ""
    return 1
end

function run_restore
    set -l restore_source "$argv[1]"
    set -l restore_uri "$argv[2]"

    if not test -d "$restore_source"
        echo "Diretorio de restore nao encontrado: $restore_source"
        exit 1
    end

    echo "Restaurando backup de $restore_source em $restore_uri..."
    mongorestore --drop --uri="$restore_uri" "$restore_source"
    or begin
        echo "Erro no mongorestore."
        exit 1
    end
end

set CMD full
if test (count $argv) -gt 0
    if string match -rq -- '^-' "$argv[1]"
        # Sem comando explicito: assume fluxo completo.
    else
        set CMD "$argv[1]"
        set -e argv[1]
    end
end

argparse 'y/yes' 'restore-uri=' 'h/help' -- $argv
or begin
    print_usage
    exit 1
end

if set -q _flag_help
    print_usage
    exit 0
end

set AUTO_YES 0
if set -q _flag_yes
    set AUTO_YES 1
end

set RESTORE_URI "$RESTORE_URI_DEFAULT"
if set -q _flag_restore_uri
    set RESTORE_URI "$_flag_restore_uri"
end

set RESTORE_INPUT "$argv[1]"

switch "$CMD"
    case full
        ensure_local_base
        ensure_ssh_ready
        run_remote_dump
        download_dump
        extract_dump

        if test $AUTO_YES -eq 1
            remove_remote_artifacts
        else if ask_yes "Remover dump do servidor remoto?"
            remove_remote_artifacts
        end

        if test $AUTO_YES -eq 1
            run_restore "$LOCAL_BASE_PATH/$DUMP_DIR" "$RESTORE_URI"
        else if ask_yes "Restaurar dump localmente?"
            run_restore "$LOCAL_BASE_PATH/$DUMP_DIR" "$RESTORE_URI"
        end

        if test $AUTO_YES -eq 1
            rm -rf "$LOCAL_BASE_PATH/$DUMP_DIR" "$LOCAL_BASE_PATH/$TAR_FILE"
        else if ask_yes "Remover dump local (pasta e tar.gz)?"
            rm -rf "$LOCAL_BASE_PATH/$DUMP_DIR" "$LOCAL_BASE_PATH/$TAR_FILE"
        end

        echo "Backup finalizado com sucesso."

    case dump-remote
        ensure_local_base
        ensure_ssh_ready
        run_remote_dump
        download_dump

        if test $AUTO_YES -eq 1
            remove_remote_artifacts
        else if ask_yes "Remover dump do servidor remoto?"
            remove_remote_artifacts
        end

        echo "Dump remoto concluido. Arquivo local: $LOCAL_BASE_PATH/$TAR_FILE"

    case restore-local
        ensure_local_base
        set -l restore_source (resolve_restore_source "$RESTORE_INPUT")
        or begin
            echo "Nao foi possivel identificar um backup para restore."
            echo "Informe um diretorio ou arquivo .tar.gz."
            exit 1
        end

        run_restore "$restore_source" "$RESTORE_URI"
        echo "Restore concluido com sucesso."

    case '*'
        echo "Comando invalido: $CMD"
        print_usage
        exit 1
end

