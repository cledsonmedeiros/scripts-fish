#!/usr/bin/env fish

# Script para download de vídeos do YouTube
# Requer: yt-dlp e ffmpeg instalados

function check_dependencies
    set -l missing_deps

    if not command -v yt-dlp &> /dev/null
        set -a missing_deps "yt-dlp"
    end

    if not command -v ffmpeg &> /dev/null
        set -a missing_deps "ffmpeg"
    end

    if test (count $missing_deps) -gt 0
        echo "❌ Dependências faltando: $missing_deps"
        echo ""
        echo "Instale com:"
        echo "  pip install yt-dlp"
        echo "  sudo apt install ffmpeg  # Debian/Ubuntu"
        echo "  brew install ffmpeg      # macOS"
        return 1
    end
    return 0
end

function list_formats
    set -l url $argv[1]
    echo "🔍 Buscando formatos disponíveis..."
    echo ""
    yt-dlp -F "$url"
end

function download_audio_mp3
    set -l url $argv[1]
    echo "🎵 Baixando apenas áudio em MP3..."
    
    # Tenta baixar áudio diretamente
    if yt-dlp -f 'ba' -x --audio-format mp3 --audio-quality 0 -o '%(title)s.%(ext)s' "$url"
        echo ""
        echo "✅ Download de áudio concluído!"
    else
        echo ""
        echo "⚠️  Falha ao baixar áudio diretamente. Tentando baixar vídeo e converter..."
        
        # Baixa vídeo e converte para MP3
        if yt-dlp -f 'bv*+ba/b' -x --audio-format mp3 --audio-quality 0 -o '%(title)s.%(ext)s' "$url"
            echo ""
            echo "✅ Vídeo baixado e convertido para MP3 com sucesso!"
        else
            echo ""
            echo "❌ Erro ao baixar e converter. Verifique a URL."
            return 1
        end
    end
end

function download_video
    set -l url $argv[1]
    set -l format_id $argv[2]
    
    echo "📹 Baixando vídeo no formato $format_id..."
    
    if yt-dlp -f "$format_id+ba/b" --merge-output-format mp4 -o '%(title)s.%(ext)s' "$url"
        echo ""
        echo "✅ Download de vídeo concluído!"
    else
        echo ""
        echo "❌ Erro ao baixar vídeo. Verifique o formato escolhido."
        return 1
    end
end

function main
    # Verifica dependências
    if not check_dependencies
        return 1
    end

    # Solicita URL
    echo "═══════════════════════════════════════════"
    echo "  YouTube Downloader - Fish Shell"
    echo "═══════════════════════════════════════════"
    echo ""
    
    if test (count $argv) -eq 0
        read -P "🔗 Cole a URL do YouTube: " url
    else
        set url $argv[1]
    end

    if test -z "$url"
        echo "❌ URL vazia. Saindo..."
        return 1
    end

    # Menu principal
    echo ""
    echo "Escolha uma opção:"
    echo "  1) Listar qualidades disponíveis"
    echo "  2) Baixar apenas áudio (MP3)"
    echo "  3) Sair"
    echo ""
    read -P "Opção [1-3]: " option

    switch $option
        case 1
            list_formats "$url"
            echo ""
            echo "───────────────────────────────────────────"
            read -P "Digite o ID do formato desejado (ex: 137): " format_id
            
            if test -z "$format_id"
                echo "❌ ID do formato vazio. Saindo..."
                return 1
            end
            
            download_video "$url" "$format_id"
            
        case 2
            download_audio_mp3 "$url"
            
        case 3
            echo "👋 Saindo..."
            return 0
            
        case '*'
            echo "❌ Opção inválida!"
            return 1
    end
end

# Executa o script
main $argv