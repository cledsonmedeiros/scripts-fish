#!/usr/bin/env fish

echo "String de conexão:"
echo "mongodb://cledson:Beta0411!@127.0.0.1:27018/rifashow?directConnection=true&authSource=admin"
echo ""
echo "Iniciando túnel SSH..."

ssh -N -L 27018:127.0.0.1:27017 -p 6969 root@45.56.112.138

