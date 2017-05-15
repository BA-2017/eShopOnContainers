#Param(
#    [parameter(Mandatory=$true)][string]$registry,
#    [parameter(Mandatory=$true)][string]$dockerUser,
#    [parameter(Mandatory=$true)][string]$dockerPassword
#)

$registry = "registry.zhaw.tk:4443"

$requiredCommands = ("docker", "docker-compose", "kubectl")
foreach ($command in $requiredCommands) {
    if ((Get-Command $command -ErrorAction SilentlyContinue) -eq $null) {
        Write-Host "$command must be on path" -ForegroundColor Red
        exit
    }
}

#Write-Host "Logging in to $registry" -ForegroundColor Yellow
#docker login -u $dockerUser -p $dockerPassword $registry
#if (-not $LastExitCode -eq 0) {
#    Write-Host "Login failed" -ForegroundColor Red
#    exit
#}

# create namespace
kubectl create namespace shop

# create registry key secret
kubectl create secret docker-registry registry-key `
    --docker-server=$registry `
    --docker-username=$dockerUser `
    --docker-password=$dockerPassword `
    --docker-email=not@used.com `
    --namespace shop

# start sql, rabbitmq, frontend deployments
kubectl create configmap config-files --from-file=nginx-conf=nginx.conf --namespace shop
kubectl label configmap config-files app=eshop --namespace shop
kubectl create -f sql-data.yaml -f rabbitmq.yaml -f services.yaml -f frontend.yaml --validate=false

Write-Host "Building and publishing eShopOnContainers..." -ForegroundColor Yellow
dotnet restore ../eShopOnContainers-ServicesAndWebApps.sln
dotnet publish -c Release -o obj/Docker/publish ../eShopOnContainers-ServicesAndWebApps.sln

Write-Host "Building Docker images..." -ForegroundColor Yellow
docker-compose -p .. -f ../docker-compose.yml build

Write-Host "Pushing images to $registry..." -ForegroundColor Yellow
$services = ("basket.api", "catalog.api", "identity.api", "ordering.api", "webmvc", "webspa")
foreach ($service in $services) {
    docker tag eshop/$service $registry/eshop/$service
    docker push $registry/eshop/$service
}

$frontendUrl = "shop.zhaw.tk:4443"

#Write-Host "Waiting for frontend's external ip..." -ForegroundColor Yellow
#while ($true) {
#    $frontendUrl = kubectl get svc frontend -o=jsonpath="{.status.loadBalancer.ingress[0].ip}"
#    if ([bool]($frontendUrl -as [ipaddress])) {
#        break
#    }
#    Start-Sleep -s 15
#}

kubectl create configmap urls `
    --from-literal=BasketUrl=http://$($frontendUrl)/basket-api `
    --from-literal=CatalogUrl=http://$($frontendUrl)/catalog-api `
    --from-literal=IdentityUrl=http://$($frontendUrl)/identity `
    --from-literal=OrderingUrl=http://$($frontendUrl)/ordering-api `
    --from-literal=MvcClient=http://$($frontendUrl)/webmvc `
    --from-literal=SpaClient=http://$($frontendUrl) `
    --namespace shop
kubectl label configmap urls app=eshop --namespace shop

Write-Host "Creating deployments..."
kubectl apply -f deployments.yaml --validate=false


Write-Host "WebSPA is exposed at http://$frontendUrl, WebMVC at http://$frontendUrl/webmvc" -ForegroundColor Yellow
