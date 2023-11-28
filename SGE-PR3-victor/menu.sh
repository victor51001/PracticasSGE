#!/bin/bash
###############################################################################
# @author https://github.com/javnitram/
# GNU GENERAL PUBLIC LICENSE Version 3
# Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)
###############################################################################

set -a # Marca variables y funciones para exportar

# VARIABLES GLOBALES
# Los nombres en SERVICES deben coincidir con los nombres de directorios en la
# ruta actual y con los servicios definidos en el fichero docker-compose.yml
# declare -a SERVICES=( odoo pgadmin4 ) No se está exportando correctamente como array
SERVICES="odoo pgadmin4" # Usar sin comillas dobles, queremos que cada valor se use independiente
RED_TEXT='\033[0;31m'
GREEN_TEXT='\033[0;32m'
RESET_TEXT='\033[0m' # No Color
VACKUP="./vackup"
PREFFIX="$( basename "$(pwd)" | tr '[:upper:]' '[:lower:]' | tr -d '.' )"
LATEST_BACKUP_CURRENT_HOST="backup_${PREFFIX}_latest_${HOSTNAME}.tgz"
BACKUPS_CURRENT_DIR_ANY_HOST="backup_${PREFFIX}_*.tgz"

# @see https://github.com/BretFisher/docker-vackup
[ -f vackup ] || curl -sSL https://raw.githubusercontent.com/BretFisher/docker-vackup/main/vackup -o "$VACKUP"
[ -x vackup ] || chmod +x "$VACKUP"

function set_permissions_for_containers() {
    # Aplicamos permisos de acceso completo a los directorios de los contenedores
    # que se usan como punto de montaje. Así nos aseguramos de que los contenedores 
    # puedan escribir y de que el usuario del anfitrión pueda acceder.
    for i in $SERVICES; do
        docker ps --quiet --filter "name=^$i" | while read -r container_id; do
            grep --fixed-strings "./$i" docker-compose.yml | cut -d: -f2 | while read -r mount; do
                    # depurar con --tty
                    echo "Estableciendo permisos en el contenedor con id $container_id basado en la imagen $i, punto de montaje $mount"
                    docker exec --privileged --user root "$container_id" sh -c "/usr/bin/find $mount -type d -exec /bin/chmod 777 {} \;" 
                    docker exec --privileged --user root "$container_id" sh -c "/usr/bin/find $mount -type f -exec /bin/chmod 666 {} \;" 
                    docker exec --privileged --user root "$container_id" sh -c "/bin/chown -R $(id -u):$(id -g) $mount"
            done
        done
    done
}

function set_permissions_for_host() {
    # Aplicamos permisos de acceso completo a los directorios del host que usamos como 
    # volúmenes de tipo bind mount para tener persistencia. Así nos aseguramos de que
    # los contenedores puedan escribir y de que el usuario del anfitrión pueda acceder.
    error="false"
    for i in $SERVICES; do
        mkdir -p "$i" || error="true"
        find "$i" -type d -exec chmod 777 {} \; || error="true"
        find "$i" -type f -exec chmod 666 {} \; || error="true"
    done

    if $error; then
        echo -ne "${RED_TEXT}"
        cat << EOF >&2
        
    Ha habido problemas al asignar algunos permisos de directorios locales. Entre otras cosas, puede afectar a:
        - La correcta ejecución de los contenedores y persistencia de sus datos.
        - La correcta migración de los ficheros usados en los puntos de montaje a otros entornos.

    Si los contenedores están en ejecución, vuelve a lanzar "$0" tras hacer "docker-compose down".
    Si no, vuelve a lanzar "$0" tras hacer "docker-compose up -d".

EOF
        # EOF debe ser una línea exacta sin caracteres delante o detrás @see sintaxis HEREDOC (<<)
        echo -ne "${RESET_TEXT}"
        exit 1
    else
        echo -e "Permisos locales asignados correctamente.\n"
    fi
}

# Esta funcion gestiona permisos de los bind mounts, almacenamiento basado el montaje 
# de ficheros o directorios del anfitrión en el contenedor.
# Los bind mounts dependen del sistema ficheros subyacente y pueden dañar el sistema anfitrión. 
# Se recomienda usar volúmenes gestionados por Docker para hacer persistentes los datos de los
# contenedores, los bind mount son apropiados para compartir ficheros de configuración y código,
# como es el caso de este proyecto.
# @see https://docs.docker.com/storage/bind-mounts/
#      https://docs.docker.com/storage/#good-use-cases-for-bind-mounts
function set_permissions() {
    chmod o+rwx . # Los usuarios de alumno aplican 750 por defecto.
    set_permissions_for_containers
    set_permissions_for_host
}

function save_backup() {
    error="false"
    chmod o+rwx . || error="true"
    if docker-compose ps -aq | grep . > /dev/null
    then
        echo "Hay contenedores en ejecución, ejecuta 'docker-compose down' antes de guardar un backup" >&2
        error="true"
    else
        sed '1,/^volumes:/d' docker-compose.yml | tr -d ' :\r' | grep -v '^#' | while read -r volume; do
            full_volume_name="${PREFFIX}_${volume}"
            "$VACKUP" export "${full_volume_name}" "${full_volume_name}.tar.gz" || error="true"
            chmod o+r "${full_volume_name}.tar.gz"
        done
        backup="backup_${PREFFIX}_$(date +%F_%H-%M)_${HOSTNAME}.tgz"
        tar --exclude='backup*.tgz' -czf "$backup" * || error="true"
        ln -f "$backup" "$LATEST_BACKUP_CURRENT_HOST" || error="true"
        sed '1,/^volumes:/d' docker-compose.yml | tr -d ' :\r' | grep -v '^#' | while read -r volume; do
            full_volume_name="${PREFFIX}_${volume}"
            rm -f "${full_volume_name}.tar.gz" || error="true"
        done
    fi

    if $error; then
        echo -ne "${RED_TEXT}"
        cat << EOF >&2
        
    Ha habido problemas al guardar el backup, revisa la traza previa.

EOF
        # EOF debe ser una línea exacta sin caracteres delante o detrás @see sintaxis HEREDOC (<<)
        echo -ne "${RESET_TEXT}"
        exit 1
    else
        echo -e "Se ha creado el fichero '$backup' y un enlace a este como '$LATEST_BACKUP_CURRENT_HOST'\n"
    fi
}

function restore_backup() {
    error="false"
    chmod o+rwx . || error="true"
    local selected_backup
    if docker-compose ps -aq | grep . > /dev/null
    then
        echo "Hay contenedores en ejecución, ejecuta 'docker-compose down' antes de restaurar un backup" >&2
        error="true"
    elif ls $BACKUPS_CURRENT_DIR_ANY_HOST >& /dev/null
    then
        selected_backup=$(ls -1r $BACKUPS_CURRENT_DIR_ANY_HOST |smenu -n20 -W $'\t\n' -N -c -b)
        echo -e "Se va a restaurar... $selected_backup"
        tar -xvzf "$selected_backup" || error="true"
        if ! error
        then
            sed '1,/^volumes:/d' docker-compose.yml | tr -d ' :\r' | grep -v '^#' | while read -r volume; do
                full_volume_name="${PREFFIX}_${volume}"
                docker volume rm "${full_volume_name}"
                chmod o+r "${full_volume_name}.tar.gz"
                "$VACKUP" import "${full_volume_name}.tar.gz" "${full_volume_name}"
                rm -f "${full_volume_name}.tar.gz" || error="true"
            done
        fi
    else
        echo "Se esperaba algún fichero con nomenclatura '$BACKUPS_CURRENT_DIR_ANY_HOST', donde '$PREFFIX' hace referencia al directorio actual" >&2
        error="true"
    fi

    if $error; then
        echo -ne "${RED_TEXT}"
        cat << EOF >&2
        
    Ha habido problemas al restaurar el backup, revisa la traza previa.

EOF
        # EOF debe ser una línea exacta sin caracteres delante o detrás @see sintaxis HEREDOC (<<)
        echo -ne "${RESET_TEXT}"
        exit 1
    else
        echo -e "Se ha restaurado el fichero '$selected_backup'\n"
    fi
}

function main() {
    while true; do
        if which smenu > /dev/null; then
            echo "CASOS DE USO COMUNES:"
            choice=$(smenu -n20 -W $'\t\n' -N -c -b -e "#.*" -g -s /set-permissions < menu.txt)
            echo -e "\n$ $choice"
            [[ "$choice" == "exit" ]] && exit 0
            bash -c "$choice" || exit $?
            echo -e "\t${GREEN_TEXT}OK${RESET_TEXT}\n"
        else
            echo "Instala el paquete smenu para que este menú sea interactivo:"
            echo -e '\t "sudo apt-get install -y smenu"'
            echo "CASOS DE USO COMUNES:"
            cat menu.txt
            exit 1
        fi
    done
}

if [ "${BASH_SOURCE[0]}" -ef "$0" ]
then
    # Están ejecutando directamente este script, no importándolo con source
    main "$@"
fi

