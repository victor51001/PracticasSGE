#!/bin/bash

cd /home/alumnotd/Escritorio/AlumnoSSD/Gestion/Repositorios/RepositorioSGE

# Obtener la fecha y hora actual
current_datetime=$(date '+%Y-%m-%d %H:%M:%S')

# Git add
git add .

# Git commit con fecha y hora actual
git commit -m "Automated commit - $current_datetime"

# Git push con nombre de usuario y token
git push "https://github.com/victor51001/PracticasSGE.git"
git push

git status 

sleep 3
