#!/usr/bin/env fish

# ========================
# CONFIGURACOES PADRAO
# ========================
set SSH_TARGET (set -q MONGO_SSH_TARGET; and echo $MONGO_SSH_TARGET; or echo acoes.cc)

set REMOTE_MONGO_URI 'mongodb://cledson:Beta0411!@127.0.0.1/rifashow?directConnection=true&authSource=admin'
set DB_NAME rifashow
set REMOTE_BASE_PATH "/root"
set LOCAL_BASE_PATH "$HOME/Downloads"
set RESTORE_URI_DEFAULT "mongodb://localhost:27017"
set S3_BUCKET_DEFAULT (set -q MONGO_S3_BUCKET; and echo $MONGO_S3_BUCKET; or echo "acoescc-dumps")
set S3_REGION_DEFAULT (set -q MONGO_S3_REGION; and echo $MONGO_S3_REGION; or echo "sa-east-1")
set S3_PREFIX_DEFAULT (set -q MONGO_S3_PREFIX; and echo $MONGO_S3_PREFIX; or echo "mongo-dumps")
set S3_PRESIGN_TTL_DEFAULT (set -q MONGO_S3_PRESIGN_TTL; and echo $MONGO_S3_PRESIGN_TTL; or echo 7200)

set DATE (date +%Y-%m-%d)
set DUMP_DIR "rifashow-$DATE"
set TAR_FILE "$DUMP_DIR.tar.gz"

function now_ts
    date +%s
end

function elapsed_hms
    set -l start_ts "$argv[1]"
    set -l end_ts (now_ts)
    set -l elapsed (math "$end_ts - $start_ts")
    if test "$elapsed" -lt 0
        set elapsed 0
    end

    set -l h (math -s0 "$elapsed / 3600")
    set -l m (math -s0 "($elapsed % 3600) / 60")
    set -l s (math -s0 "$elapsed % 60")
    printf "%02d:%02d:%02d" $h $m $s
end

function file_size_bytes
    set -l file "$argv[1]"

    if test -f "$file"
        set -l size (stat -f%z "$file" 2>/dev/null)
        if test $status -eq 0 -a -n "$size"
            echo "$size"
            return 0
        end

        set size (stat -c%s "$file" 2>/dev/null)
        if test $status -eq 0 -a -n "$size"
            echo "$size"
            return 0
        end
    end

    echo ""
    return 1
end

function extract_archive_with_progress
    set -l archive_file "$argv[1]"
    set -l output_dir "$argv[2]"

    if not test -f "$archive_file"
        return 1
    end

    set -l archive_size (file_size_bytes "$archive_file")

    if type -q pv
        if type -q pigz
            if test -n "$archive_size"
                pv -s "$archive_size" "$archive_file" | pigz -dc | tar -xf - -C "$output_dir"
            else
                pv "$archive_file" | pigz -dc | tar -xf - -C "$output_dir"
            end
        else
            if test -n "$archive_size"
                pv -s "$archive_size" "$archive_file" | tar -xzf - -C "$output_dir"
            else
                pv "$archive_file" | tar -xzf - -C "$output_dir"
            end
        end
    else
        tar -xzf "$archive_file" -C "$output_dir"
    end
end

function print_usage
    echo "Uso:"
    echo "  mongo-dump-remote.fish full [--yes] [--restore-uri URI] [--s3 ...]"
    echo "  mongo-dump-remote.fish dump-remote [--s3 ...]"
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
    echo "  --s3                  Usa S3 como canal principal de transferencia (padrao: ativo)"
    echo "  --s3-bucket=BUCKET    Bucket S3 (padrao: acoescc-dumps ou MONGO_S3_BUCKET)"
    echo "  --s3-region=REGIAO    Regiao AWS (padrao: $S3_REGION_DEFAULT)"
    echo "  --s3-prefix=PREFIXO   Prefixo S3 para objetos (padrao: $S3_PREFIX_DEFAULT)"
    echo "  --s3-presign-download Baixa no local via URL pre-assinada + curl (padrao no modo --s3)"
    echo "  --s3-aws-download     Forca download local via aws cli"
    echo "  --s3-presign-ttl=SEG  TTL da URL pre-assinada (padrao: $S3_PRESIGN_TTL_DEFAULT)"
    echo "  --keep-s3             Mantem objeto no S3 mesmo apos restore com sucesso"
    echo ""
    echo "Exemplos:"
    echo "  mongo-dump-remote.fish dump-remote"
    echo "  mongo-dump-remote.fish dump-remote --s3 --s3-bucket=acoescc-dumps"
    echo "  mongo-dump-remote.fish dump-remote --s3 --s3-bucket=acoescc-dumps --s3-presign-download"
    echo "  mongo-dump-remote.fish restore-local ~/Downloads/rifashow-2026-03-10"
    echo "  mongo-dump-remote.fish restore-local ~/Downloads/rifashow-2026-03-10.tar.gz"
    echo "  mongo-dump-remote.fish full --yes"
    echo "  mongo-dump-remote.fish full --yes --s3 --s3-bucket=acoescc-dumps --s3-region=sa-east-1"
end

function ensure_local_base
    if not test -d "$LOCAL_BASE_PATH"
        mkdir -p "$LOCAL_BASE_PATH"
    end
end

function ensure_ssh_ready
    echo "Verificando autenticacao SSH por alias: $SSH_TARGET"
    ssh -o BatchMode=yes "$SSH_TARGET" "echo ok" >/dev/null 2>&1
    or begin
        echo "Falha ao autenticar via SSH usando '$SSH_TARGET'."
        echo "Verifique sua entrada no ~/.ssh/config e a chave associada."
        exit 1
    end
end

function check_local_tool
    set -l tool_name "$argv[1]"
    if type -q "$tool_name"
        echo "  [OK] local: $tool_name"
        return 0
    end

    echo "  [FALTA] local: $tool_name"
    return 1
end

function check_remote_tool
    set -l tool_name "$argv[1]"
    ssh "$SSH_TARGET" "command -v '$tool_name' >/dev/null 2>&1"
    if test $status -eq 0
        echo "  [OK] remoto: $tool_name"
        return 0
    end

    echo "  [FALTA] remoto: $tool_name"
    return 1
end

function s3_object_key
    set -l prefix (string trim -c '/' -- "$S3_PREFIX")
    if test -n "$prefix"
        echo "$prefix/$TAR_FILE"
    else
        echo "$TAR_FILE"
    end
end

function s3_object_uri
    set -l key (s3_object_key)
    echo "s3://$S3_BUCKET/$key"
end

function preflight_s3_local
    if test -z "$S3_BUCKET"
        echo "Preflight S3 falhou: bucket nao informado. Use --s3-bucket ou MONGO_S3_BUCKET."
        exit 1
    end

    if test $S3_USE_PRESIGN -eq 1
        if type -q curl
            echo "  [OK] local: curl (download via URL pre-assinada)"
        else if type -q aws
            echo "  [INFO] curl ausente; usando fallback para aws cli local"
            set -g S3_USE_PRESIGN 0
        else
            echo "Preflight S3 local falhou: instale curl (modo padrao) ou aws cli local."
            exit 1
        end
    end

    if test $S3_USE_PRESIGN -eq 1
        echo "  [OK] modo local: URL pre-assinada + curl"
    else
        check_local_tool aws
        or exit 1
        aws s3api head-bucket --bucket "$S3_BUCKET" --region "$S3_REGION" >/dev/null 2>&1
        or begin
            echo "Preflight S3 local falhou: sem acesso ao bucket '$S3_BUCKET' na regiao '$S3_REGION'."
            exit 1
        end
        echo "  [OK] local: acesso ao bucket S3 confirmado"
    end
end

function preflight_s3_remote
    check_remote_tool aws
    or exit 1

    ssh "$SSH_TARGET" "aws s3api head-bucket --bucket '$S3_BUCKET' --region '$S3_REGION' >/dev/null 2>&1"
    or begin
        echo "Preflight S3 remoto falhou: sem acesso ao bucket '$S3_BUCKET' na regiao '$S3_REGION'."
        exit 1
    end

    echo "  [OK] remoto: acesso ao bucket S3 confirmado"
end

function preflight_dump_remote
    set -l missing 0

    echo "Preflight (local):"
    for t in ssh scp tar
        check_local_tool "$t"
        or set missing 1
    end

    if type -q rsync
        echo "  [OK] local opcional: rsync (download mais rapido)"
    else
        echo "  [INFO] local opcional ausente: rsync (usando scp)"
    end

    if type -q pv
        echo "  [OK] local opcional: pv (barra de progresso/ETA)"
    else
        echo "  [INFO] local opcional ausente: pv (sem barra detalhada)"
    end

    if type -q pigz
        echo "  [OK] local opcional: pigz (descompactacao paralela)"
    else
        echo "  [INFO] local opcional ausente: pigz (usando gzip/tar padrao)"
    end

    ensure_ssh_ready

    echo "Preflight (remoto):"
    for t in mongodump tar du awk
        check_remote_tool "$t"
        or set missing 1
    end

    if ssh "$SSH_TARGET" "command -v pigz >/dev/null 2>&1"
        echo "  [OK] remoto opcional: pigz (compactacao paralela)"
    else
        echo "  [INFO] remoto opcional ausente: pigz (fallback para gzip/tar)"
    end

    if ssh "$SSH_TARGET" "command -v pv >/dev/null 2>&1"
        echo "  [OK] remoto opcional: pv (barra de progresso/ETA)"
    else
        echo "  [INFO] remoto opcional ausente: pv (sem barra detalhada)"
    end

    if test $missing -ne 0
        echo ""
        echo "Preflight falhou: faltam dependencias obrigatorias."
        exit 1
    end

    if test $USE_S3 -eq 1
        echo "Preflight (S3):"
        preflight_s3_local
        preflight_s3_remote
    end
end

function preflight_restore_local
    set -l missing 0

    echo "Preflight (local):"
    for t in mongorestore tar
        check_local_tool "$t"
        or set missing 1
    end

    if type -q pv
        echo "  [OK] local opcional: pv (barra de progresso/ETA)"
    else
        echo "  [INFO] local opcional ausente: pv (sem barra detalhada)"
    end

    if type -q pigz
        echo "  [OK] local opcional: pigz (descompactacao paralela)"
    else
        echo "  [INFO] local opcional ausente: pigz (usando gzip/tar padrao)"
    end

    if test $missing -ne 0
        echo ""
        echo "Preflight falhou: faltam dependencias obrigatorias."
        exit 1
    end
end

function preflight_full
    preflight_dump_remote

    if type -q mongorestore
        echo "  [OK] local opcional para full: mongorestore (restore local)"
    else
        echo "  [INFO] local opcional ausente para full: mongorestore"
        echo "        Se voce escolher restaurar, esta etapa vai falhar."
    end
end

function upload_dump_to_s3_remote
    set -l s3_uri (s3_object_uri)
    echo "Enviando dump remoto para S3: $s3_uri"
    set -l started_at (now_ts)

    ssh "$SSH_TARGET" "aws s3 cp '$REMOTE_BASE_PATH/$TAR_FILE' '$s3_uri' --region '$S3_REGION'"
    or begin
        echo "Falha no upload para S3. O script vai tentar fallback de download direto por SSH."
        return 1
    end

    echo "Upload para S3 finalizado em "(elapsed_hms "$started_at")"."
    return 0
end

function download_dump_ssh
    set -l downloaded 0

    if type -q rsync
        # rsync nativo do macOS costuma ser antigo (2.6.x) e nao suporta --append-verify/--info=progress2.
        if rsync --version 2>/dev/null | head -n 1 | grep -q 'version 3'
            rsync -ah --partial --append-verify --info=progress2 --rsh="ssh -T -c aes128-gcm@openssh.com -o Compression=no" "$SSH_TARGET:$REMOTE_BASE_PATH/$TAR_FILE" "$LOCAL_BASE_PATH/$TAR_FILE"
        else
            rsync -ah --partial --progress --rsh="ssh -T -c aes128-gcm@openssh.com -o Compression=no" "$SSH_TARGET:$REMOTE_BASE_PATH/$TAR_FILE" "$LOCAL_BASE_PATH/$TAR_FILE"
        end

        if test $status -eq 0
            set downloaded 1
        else
            echo "Rsync falhou. Tentando fallback com scp..."
            scp -c aes128-gcm@openssh.com -o Compression=no "$SSH_TARGET:$REMOTE_BASE_PATH/$TAR_FILE" "$LOCAL_BASE_PATH/"
            if test $status -eq 0
                set downloaded 1
            end
        end
    else
        echo "Rsync indisponivel. Usando scp..."
        scp -c aes128-gcm@openssh.com -o Compression=no "$SSH_TARGET:$REMOTE_BASE_PATH/$TAR_FILE" "$LOCAL_BASE_PATH/"
        if test $status -eq 0
            set downloaded 1
        end
    end

    if test $downloaded -ne 1
        return 1
    end

    return 0
end

function download_dump_s3
    set -l s3_uri (s3_object_uri)

    if test $S3_USE_PRESIGN -eq 1
        echo "Baixando do S3 via URL pre-assinada (curl com progresso): $s3_uri"

        set -l presign_url (ssh "$SSH_TARGET" "aws s3 presign '$s3_uri' --region '$S3_REGION' --expires-in '$S3_PRESIGN_TTL'")
        or begin
            echo "Falha ao gerar URL pre-assinada no servidor remoto."
            return 1
        end

        set presign_url (string trim -- "$presign_url")
        if test -z "$presign_url"
            echo "URL pre-assinada vazia."
            return 1
        end

        curl -fL --progress-bar "$presign_url" -o "$LOCAL_BASE_PATH/$TAR_FILE"
        or return 1
    else
        if type -q aws
            echo "Baixando do S3 via aws cli (com progresso): $s3_uri"
            aws s3 cp "$s3_uri" "$LOCAL_BASE_PATH/$TAR_FILE" --region "$S3_REGION"
            or return 1
        else
            if not type -q curl
                echo "Sem aws cli local e sem curl para modo presign."
                return 1
            end

            echo "aws cli local nao encontrado. Tentando URL pre-assinada + curl..."
            set -l presign_url_auto (ssh "$SSH_TARGET" "aws s3 presign '$s3_uri' --region '$S3_REGION' --expires-in '$S3_PRESIGN_TTL'")
            or return 1

            set presign_url_auto (string trim -- "$presign_url_auto")
            test -n "$presign_url_auto"
            or return 1

            curl -fL --progress-bar "$presign_url_auto" -o "$LOCAL_BASE_PATH/$TAR_FILE"
            or return 1
        end
    end

    return 0
end

function remove_s3_object
    set -l s3_uri (s3_object_uri)
    echo "Removendo objeto temporario no S3: $s3_uri"
    ssh "$SSH_TARGET" "aws s3 rm '$s3_uri' --region '$S3_REGION'"
    or begin
        echo "Falha ao remover objeto S3 temporario: $s3_uri"
        return 1
    end
    return 0
end

function run_remote_dump
    echo "Gerando dump e compactando no servidor remoto (com progresso quando disponivel)..."
    set -l started_at (now_ts)

    begin
        echo "set -e"
        echo "cd '$REMOTE_BASE_PATH'"
        echo "rm -rf '$DUMP_DIR' '$TAR_FILE'"
        echo "echo '[1/3] Executando mongodump...'"
        echo "mongodump --uri='$REMOTE_MONGO_URI' --db '$DB_NAME' -o './$DUMP_DIR'"
        echo ""
        echo "dump_size=\$(du -sb '$DUMP_DIR' 2>/dev/null | awk '{print \$1}')"
        echo "if [ -n \"\$dump_size\" ]; then"
        echo "    dump_size_gb=\$(awk -v s=\"\$dump_size\" 'BEGIN {printf \"%.2f\", s/1024/1024/1024}')"
        echo "    printf '[2/3] Compactando dump - estimado bruto: %s bytes (%s GB)...\\n' \"\$dump_size\" \"\$dump_size_gb\""
        echo "else"
        echo "    echo '[2/3] Compactando dump - estimado bruto: desconhecido bytes...'"
        echo "fi"
        echo ""
        echo "if command -v pigz >/dev/null 2>&1; then"
        echo "    if command -v pv >/dev/null 2>&1 && [ -n \"\$dump_size\" ]; then"
        echo "        tar -cf - '$DUMP_DIR' | pv -s \"\$dump_size\" | pigz -1 > '$TAR_FILE'"
        echo "    else"
        echo "        tar -cf - '$DUMP_DIR' | pigz -1 > '$TAR_FILE'"
        echo "    fi"
        echo "else"
        echo "    if command -v pv >/dev/null 2>&1 && [ -n \"\$dump_size\" ]; then"
        echo "        if command -v gzip >/dev/null 2>&1; then"
        echo "            tar -cf - '$DUMP_DIR' | pv -s \"\$dump_size\" | gzip -1 > '$TAR_FILE'"
        echo "        else"
        echo "            tar -czf '$TAR_FILE' '$DUMP_DIR'"
        echo "        fi"
        echo "    else"
        echo "        tar -czf '$TAR_FILE' '$DUMP_DIR'"
        echo "    fi"
        echo "fi"
        echo ""
        echo "tar_size=\$(du -h '$TAR_FILE' | awk '{print \$1}')"
        echo "echo '[3/3] Compactacao finalizada:' '$TAR_FILE' \$tar_size"
    end | ssh "$SSH_TARGET" sh
    or begin
        echo "Erro ao gerar dump remoto."
        exit 1
    end

    echo "Dump remoto finalizado em "(elapsed_hms "$started_at")"."
end

function download_dump
    echo "Baixando dump para $LOCAL_BASE_PATH (com progresso)..."
    set -l started_at (now_ts)
    set -l downloaded_ok 0

    if test $USE_S3 -eq 1
        download_dump_s3
        if test $status -eq 0
            set downloaded_ok 1
        else
            echo "Download via S3 falhou. Tentando fallback por rsync/scp..."
            download_dump_ssh
            if test $status -eq 0
                set downloaded_ok 1
            end
        end
    else
        download_dump_ssh
        if test $status -eq 0
            set downloaded_ok 1
        end
    end

    if test $downloaded_ok -ne 1
        echo "Erro no download do dump (S3 e fallback SSH)."
        exit 1
    end

    echo "Download finalizado em "(elapsed_hms "$started_at")"."
end

function extract_dump
    echo "Descompactando $TAR_FILE..."
    set -l started_at (now_ts)

    extract_archive_with_progress "$LOCAL_BASE_PATH/$TAR_FILE" "$LOCAL_BASE_PATH"
    or begin
        echo "Erro ao descompactar dump local."
        exit 1
    end

    echo "Descompactacao finalizada em "(elapsed_hms "$started_at")"."
end

function remove_remote_artifacts
    ssh "$SSH_TARGET" "rm -rf '$REMOTE_BASE_PATH/$DUMP_DIR' '$REMOTE_BASE_PATH/$TAR_FILE'" >/dev/null 2>&1
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
                extract_archive_with_progress "$input_path" "$LOCAL_BASE_PATH"
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

argparse 'y/yes' 'restore-uri=' 'h/help' 's3' 's3-bucket=' 's3-region=' 's3-prefix=' 's3-presign-download' 's3-aws-download' 's3-presign-ttl=' 'keep-s3' -- $argv
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

set USE_S3 1
if set -q _flag_s3
    set USE_S3 1
end

set S3_BUCKET "$S3_BUCKET_DEFAULT"
if set -q _flag_s3_bucket
    set S3_BUCKET "$_flag_s3_bucket"
end

set S3_REGION "$S3_REGION_DEFAULT"
if set -q _flag_s3_region
    set S3_REGION "$_flag_s3_region"
end

set S3_PREFIX "$S3_PREFIX_DEFAULT"
if set -q _flag_s3_prefix
    set S3_PREFIX "$_flag_s3_prefix"
end

set S3_PRESIGN_TTL "$S3_PRESIGN_TTL_DEFAULT"
if set -q _flag_s3_presign_ttl
    set S3_PRESIGN_TTL "$_flag_s3_presign_ttl"
end

set S3_USE_PRESIGN 1
if set -q _flag_s3_presign_download
    set S3_USE_PRESIGN 1
end
if set -q _flag_s3_aws_download
    set S3_USE_PRESIGN 0
end

set KEEP_S3 0
if set -q _flag_keep_s3
    set KEEP_S3 1
end

if test $USE_S3 -eq 1
    if test -z "$S3_BUCKET"
        echo "Modo S3 ativo, mas bucket vazio. Use --s3-bucket ou MONGO_S3_BUCKET."
        exit 1
    end
    if test $S3_USE_PRESIGN -eq 1
        echo "Modo S3 ativo: bucket=$S3_BUCKET regiao=$S3_REGION prefixo=$S3_PREFIX download=presign+curl"
    else
        echo "Modo S3 ativo: bucket=$S3_BUCKET regiao=$S3_REGION prefixo=$S3_PREFIX download=aws-cli"
    end
end

set RESTORE_INPUT "$argv[1]"

switch "$CMD"
    case full
        ensure_local_base
        preflight_full
        run_remote_dump

        if test $USE_S3 -eq 1
            upload_dump_to_s3_remote
        end

        download_dump
        extract_dump

        set -l restored_success 0

        if test $AUTO_YES -eq 1
            remove_remote_artifacts
        else if ask_yes "Remover dump do servidor remoto?"
            remove_remote_artifacts
        end

        if test $AUTO_YES -eq 1
            run_restore "$LOCAL_BASE_PATH/$DUMP_DIR" "$RESTORE_URI"
            set restored_success 1
        else if ask_yes "Restaurar dump localmente?"
            run_restore "$LOCAL_BASE_PATH/$DUMP_DIR" "$RESTORE_URI"
            set restored_success 1
        end

        if test $USE_S3 -eq 1; and test $restored_success -eq 1; and test $KEEP_S3 -ne 1
            remove_s3_object
        end

        if test $AUTO_YES -eq 1
            rm -rf "$LOCAL_BASE_PATH/$DUMP_DIR" "$LOCAL_BASE_PATH/$TAR_FILE"
        else if ask_yes "Remover dump local (pasta e tar.gz)?"
            rm -rf "$LOCAL_BASE_PATH/$DUMP_DIR" "$LOCAL_BASE_PATH/$TAR_FILE"
        end

        echo "Backup finalizado com sucesso."

    case dump-remote
        ensure_local_base
        preflight_dump_remote
        run_remote_dump

        if test $USE_S3 -eq 1
            upload_dump_to_s3_remote
        end

        download_dump

        if test $AUTO_YES -eq 1
            remove_remote_artifacts
        else if ask_yes "Remover dump do servidor remoto?"
            remove_remote_artifacts
        end

        if test $USE_S3 -eq 1
            echo "Dump remoto concluido. Arquivo local: $LOCAL_BASE_PATH/$TAR_FILE"
            echo "Objeto S3: "(s3_object_uri)
        else
            echo "Dump remoto concluido. Arquivo local: $LOCAL_BASE_PATH/$TAR_FILE"
        end

    case restore-local
        ensure_local_base
        preflight_restore_local
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

