# Docker
Must be running Windows containers
docker run -e accept_eula=Y -p 7049:7049 -p 7048:7048 -p 8080:8080 --name buscent --memory 6g -d bc3rcm16:latest


Lots of trouble trying to set fixed IP. Instead, just edit hosts
docker inspect -f "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}" buscent | clip
Add to hosts: buscent     ....
http://buscent/BC/?tenant=default


# Business Central Setup
Login: admin/password  
Search (Alt+Q) for "Extension Management"
Install 'Any' and 'Library Assert' by click on 3 dots, install