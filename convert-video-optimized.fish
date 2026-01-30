#!/usr/bin/env fish

function convert_optimized
    if test (count $argv) -ne 1
        echo "Uso: convert_optimized <arquivo.mp4>"
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

    # Obtém tamanho do arquivo original
    set original_size (stat -f%z "$input_file" 2>/dev/null || stat -c%s "$input_file" 2>/dev/null)

    ffmpeg -i "$input_file" \
        -c:v libx264 -profile:v baseline -level 3.1 \
        -pix_fmt yuv420p \
        -movflags +faststart \
        -crf 23 \
        -c:a aac -b:a 128k \
        "$output_file"

    if test $status -eq 0
        echo ""
        echo "Arquivo convertido com sucesso: $output_file"
        echo ""

        # Obtém tamanho do arquivo convertido
        set converted_size (stat -f%z "$output_file" 2>/dev/null || stat -c%s "$output_file" 2>/dev/null)

        # Calcula e exibe diferença de tamanho
        set original_mb (math "$original_size / 1048576")
        set converted_mb (math "$converted_size / 1048576")
        set diff_mb (math "$original_mb - $converted_mb")
        set percentage (math "($diff_mb / $original_mb) * 100")

        echo "Tamanho original: "(printf "%.2f MB" $original_mb)
        echo "Tamanho convertido: "(printf "%.2f MB" $converted_mb)
        
        if test $diff_mb -gt 0
            echo "Redução: "(printf "%.2f MB (%.1f%%)" $diff_mb $percentage)
        else
            set increase_mb (math "$converted_mb - $original_mb")
            set increase_percentage (math "($increase_mb / $original_mb) * 100")
            echo "Aumento: "(printf "%.2f MB (%.1f%%)" $increase_mb $increase_percentage)
        end
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
convert_optimized $argv
