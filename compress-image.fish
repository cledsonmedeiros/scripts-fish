#!/opt/homebrew/bin/fish

function compress_image
    # Verifica se o ImageMagick está instalado
    if not command -q magick
        echo "Erro: ImageMagick não está instalado."
        echo ""
        echo "Para instalar o ImageMagick:"
        echo "  • macOS (Homebrew): brew install imagemagick"
        echo "  • Ubuntu/Debian: sudo apt install imagemagick"
        echo "  • CentOS/RHEL: sudo yum install ImageMagick"
        echo "  • Fedora: sudo dnf install ImageMagick"
        echo ""
        echo "Após a instalação, execute o script novamente."
        return 1
    end

    if test (count $argv) -ne 1
        echo "Uso: compress_image <arquivo_imagem>"
        echo "Formatos suportados: jpg, jpeg, png, tiff, bmp, webp"
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

    # Verifica se é um arquivo de imagem suportado
    set extension (string lower (string split -r -m1 . (basename $input_file))[2])
    if not contains $extension jpg jpeg png tiff bmp webp
        echo "Erro: formato '$extension' não suportado."
        echo "Formatos suportados: jpg, jpeg, png, tiff, bmp, webp"
        return 1
    end

    # Extrai nome base e extensão
    set base (basename $input_file .$extension)
    set dir (dirname $input_file)
    
    # Para máxima compressão, sempre salva como JPEG (exceto se for PNG com transparência)
    set output_extension "jpg"
    set output_file "$dir/$base-compressed.$output_extension"

    echo "Comprimindo imagem: $input_file"
    echo "Arquivo de saída: $output_file"
    echo "Reduzindo resolução para máximo 1280x1280 pixels"
    echo ""

    # Compressão otimizada com resolução menor
    # -strip: remove metadados
    # -quality 75: boa qualidade com compressão significativa
    # -resize 1280x1280>: resolução menor (era 1920x1920)
    # -format jpeg: força conversão para JPEG (mais compacto)
    magick "$input_file" -strip -resize '1280x1280>' -quality 75 -format jpeg "$output_file"

    if test $status -eq 0
        echo ""
        echo "Imagem comprimida com sucesso: $output_file"
        
        # Mostra informações sobre a compressão
        set original_size (stat -f%z "$input_file")
        set compressed_size (stat -f%z "$output_file")
        set reduction (math "round(($original_size - $compressed_size) * 100 / $original_size)")
        
        echo "Tamanho original: "(numfmt --to=iec $original_size)
        echo "Tamanho comprimido: "(numfmt --to=iec $compressed_size)
        echo "Redução: $reduction%"
        echo ""

        # Copia a imagem comprimida para o clipboard
        if command -q pbcopy
            cat "$output_file" | pbcopy
            echo "✅ Imagem copiada para o clipboard! Use Cmd+V para colar."
        else
            echo "⚠️  Clipboard não disponível (comando pbcopy não encontrado)."
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
        echo "Erro na compressão da imagem."
        return 1
    end
end

# Executa diretamente se chamado como script
compress_image $argv