#!/opt/homebrew/bin/fish

function convert_to_mp3
    if test (count $argv) -ne 1
        echo "Uso: convert_to_mp3 <arquivo_video>"
        return 1
    end

    set input_file $argv[1]

    # Converte para caminho absoluto se for relativo
    if not string match -q '/*' $input_file
        set input_file (realpath $input_file)
    end

    if not test -f $input_file
        echo "Erro: arquivo '$input_file' não encontrado."
        return 1
    end

    # Extrai nome base (sem extensão) e diretório
    set base (basename $input_file | sed 's/\.[^.]*$//')
    set dir (dirname $input_file)
    set output_file "$dir/$base.mp3"

    echo "Convertendo vídeo para MP3: $input_file"
    echo "Arquivo de saída: $output_file"
    echo ""

    ffmpeg -i "$input_file" -vn -map_metadata -1 -c:a libmp3lame -q:a 2 "$output_file"

    if test $status -eq 0
        echo ""
        echo "Áudio extraído com sucesso: $output_file"
    else
        echo ""
        echo "Erro na conversão do arquivo."
        return 1
    end
end

# Executa diretamente se chamado como script
convert_to_mp3 $argv