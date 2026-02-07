#!/opt/homebrew/bin/fish

# ===============================
# CONFIGURAÇÕES GERAIS
# ===============================
set MAX_JOBS (sysctl -n hw.ncpu 2>/dev/null || nproc)
set DELETE_ORIGINAL "no"
set PROMPT_DELETE "yes"

argparse -n compress-video 'd/delete' 'k/keep' 'j/jobs=' -- $argv
or exit 2

if set -q _flag_jobs
    set MAX_JOBS $_flag_jobs
end

if set -q _flag_delete
    set DELETE_ORIGINAL "yes"
    set PROMPT_DELETE "no"
end

if set -q _flag_keep
    set DELETE_ORIGINAL "no"
    set PROMPT_DELETE "no"
end

if test "$PROMPT_DELETE" = "yes"
    echo "Deseja apagar o vídeo original após conversão bem-sucedida? (y/N)"
    read -l answer

    switch (string lower $answer)
        case y yes
            set DELETE_ORIGINAL "yes"
            echo "✔ Originais SERÃO apagados"
        case '*'
            echo "✔ Originais SERÃO mantidos"
    end
else
    if test "$DELETE_ORIGINAL" = "yes"
        echo "✔ Originais SERÃO apagados"
    else
        echo "✔ Originais SERÃO mantidos"
    end
end

echo "Usando até $MAX_JOBS conversões simultâneas"

# ===============================
# FUNÇÕES
# ===============================
function is_video
    ffprobe -v error \
        -select_streams v:0 \
        -show_entries stream=index \
        -of csv=p=0 "$argv[1]" >/dev/null 2>&1
end

function convert_one
    set input_file $argv[1]

    if string match -q '*-out.mp4' $input_file
        return
    end

    if not is_video $input_file
        return
    end

    set dir (dirname $input_file)
    set base (basename $input_file)
    set name (string replace -r '\.[^.]+$' '' $base)
    set output_file "$dir/$name-out.mp4"

    if test -f $output_file
        return
    end

    echo "🎬 Convertendo: $input_file"

    ffmpeg -y \
        -i "$input_file" \
        -map_metadata -1 \
        -map_chapters -1 \
        -metadata title= \
        -metadata artist= \
        -metadata author= \
        -metadata comment= \
        -metadata:s:v:0 handler_name= \
        -metadata:s:a:0 handler_name= \
        -c:v libx264 \
        -profile:v baseline \
        -level 3.0 \
        -pix_fmt yuv420p \
        -preset veryfast \
        -tune film \
        -crf 24 \
        -movflags +faststart \
        -threads 0 \
        -c:a aac \
        -b:a 96k \
        "$output_file"

    if test $status -eq 0
        # Preserva data original
        touch -r "$input_file" "$output_file"

        if test "$DELETE_ORIGINAL" = "yes"
            rm "$input_file"
        end

        echo "✔ Finalizado: $output_file"
    else
        echo "✖ Erro: $input_file"
    end
end

# ===============================
# EXECUÇÃO
# ===============================
if test (count $argv) -ne 1
    echo "Uso: convert-video.fish [--delete|--keep] [--jobs N] <arquivo ou pasta>"
    exit 1
end

set TARGET $argv[1]

if test -d $TARGET
    set -l func_file (mktemp -t compress-video.XXXXXX.fish)
    functions is_video convert_one >"$func_file"

    find "$TARGET" -type f | \
        xargs -n 1 -P $MAX_JOBS fish -c 'source "$argv[1]"; convert_one "$argv[2]"' _ "$func_file"

    rm "$func_file"
else if test -f $TARGET
    convert_one "$TARGET"
else
    echo "Arquivo ou pasta não encontrada"
end
