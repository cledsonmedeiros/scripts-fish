#!/opt/homebrew/bin/fish

function convert_clean
    if test (count $argv) -ne 1
        echo "Uso: convert_clean <arquivo.mp4>"
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

    # Extrai nome base e extensão
    set base (basename $input_file .mp4)
    set dir (dirname $input_file)
    set output_file "$dir/$base-out.mp4"

    echo "Convertendo arquivo: $input_file"
    echo "Arquivo de saída: $output_file"
    echo ""

    ffmpeg -i "$input_file" -map_metadata -1 -map_chapters -1 -c:v libx264 -crf 23 -preset medium -c:a aac -b:a 128k "$output_file"

    if test $status -eq 0
        echo ""
        echo "Arquivo convertido com sucesso: $output_file"
        echo ""

        # Pergunta se deve remover o original
        read -P "Deseja remover o arquivo original '$input_file'? [s/N] " -l resposta
        
        switch (string lower (string trim $resposta))
            case s sim
                rm "$input_file"
                echo "Arquivo original removido."
            case '*'
                echo "Arquivo original mantido."
        end
    else
        echo ""
        echo "Erro na conversão do arquivo."
        return 1
    end
end

# Executa diretamente se chamado como script
convert_clean $argv