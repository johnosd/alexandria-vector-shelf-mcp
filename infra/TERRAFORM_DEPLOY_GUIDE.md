# Terraform no GCP — Guia
Siga cada passo em ordem. Não pule etapas.

---

## O que você vai ter no final

Uma infraestrutura completa do alexandria-vector-shelf-mcp rodando no GCP:
- Cloud Run (ingestion + chat services)
- Firestore (database + vector index)
- Firebase Storage (bucket de epubs)
- IAM (service accounts com permissões corretas)

Tempo estimado: 45–60 minutos na primeira vez.

---

## PARTE 1 — Instalar as ferramentas

### 1.1 — Instalar o Google Cloud CLI (gcloud)

O `gcloud` é a ferramenta de linha de comando do GCP. Você vai precisar dela
para autenticar o Terraform e para alguns comandos manuais.

**macOS:**
```bash
brew install google-cloud-sdk
```

**Linux (Ubuntu/Debian):**
```bash
curl https://sdk.cloud.google.com | bash
exec -l $SHELL
```

**Windows:**
Baixe o instalador em: https://cloud.google.com/sdk/docs/install
Execute o instalador e siga as instruções.

**Verificar instalação:**
```bash
gcloud --version
# Deve mostrar: Google Cloud SDK 460.x.x ou similar
```

---

### 1.2 — Instalar o Terraform

**macOS:**
```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
```

**Linux (Ubuntu/Debian):**
```bash
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list

sudo apt update && sudo apt install terraform
```

**Windows:**
Baixe o binário em: https://developer.hashicorp.com/terraform/install
Extraia e adicione ao PATH do sistema.

**Verificar instalação:**
```bash
terraform --version
# Deve mostrar: Terraform v1.6.x ou mais recente
```

---

## PARTE 2 — Configurar o Google Cloud

### 2.1 — Criar uma conta no Google Cloud

1. Acesse: https://console.cloud.google.com
2. Faça login com sua conta Google
3. Se for a primeira vez, aceite os termos de serviço
4. O GCP oferece $300 de crédito gratuito por 90 dias para novos usuários

---

### 2.2 — Criar um projeto no GCP

Um projeto é o contêiner de todos os seus recursos no GCP.

1. No console GCP, clique no seletor de projetos no topo da página
   (onde diz "Select a project" ou o nome do projeto atual)
2. Clique em **New Project**
3. Preencha:
   - **Project name:** `alexandria-vector-shelf-mcp`
   - **Project ID:** anote este valor — você vai usar em todos os comandos
     (o GCP pode sugerir algo como `alexandria-vector-shelf-12345`)
4. Clique em **Create**
5. Aguarde alguns segundos até o projeto ser criado
6. Selecione o novo projeto no seletor

> ⚠️ O Project ID é diferente do Project Name. Anote o ID — é ele que vai
> no arquivo `dev.tfvars`.

---

### 2.3 — Ativar o faturamento (billing)

O Terraform precisa criar recursos que requerem billing ativo, mesmo que
você esteja dentro do free tier.

1. No console GCP, vá em **Billing** no menu lateral
2. Se não tiver uma conta de billing, clique em **Create account**
3. Adicione um cartão de crédito (não será cobrado dentro do free tier)
4. Vincule a conta de billing ao seu projeto:
   - **Billing → My projects → Actions → Change billing**

---

### 2.4 — Instalar o Firebase CLI

Precisamos do Firebase CLI para algumas configurações que o Terraform não
gerencia (Auth, Security Rules).

```bash
npm install -g firebase-tools
```

Se não tiver Node.js:
```bash
# macOS
brew install node

# Ubuntu/Debian
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
sudo apt install -y nodejs
```

**Verificar:**
```bash
firebase --version
# Deve mostrar: 13.x.x ou similar
```

---

## PARTE 3 — Autenticar as ferramentas

### 3.1 — Autenticar o gcloud

```bash
# Login com sua conta Google (abre o browser)
gcloud auth login

# Definir o projeto padrão (substitua pelo seu Project ID)
gcloud config set project SEU-PROJECT-ID

# Verificar que o projeto está correto
gcloud config get project
# Deve mostrar o seu Project ID
```

---

### 3.2 — Criar credenciais para o Terraform

O Terraform precisa de credenciais para criar recursos no GCP.
Usamos Application Default Credentials (ADC) — é o método recomendado.

```bash
gcloud auth application-default login
```

Este comando vai:
1. Abrir o browser
2. Pedir para você fazer login
3. Salvar as credenciais em `~/.config/gcloud/application_default_credentials.json`

O Terraform vai usar esse arquivo automaticamente — você não precisa
configurar mais nada.

**Verificar:**
```bash
gcloud auth application-default print-access-token
# Deve imprimir um token longo. Se funcionar, está autenticado.
```

---

### 3.3 — Autenticar o Firebase CLI

```bash
firebase login
# Abre o browser, faça login com a mesma conta Google
```

---

## PARTE 4 — Preparar o projeto Firebase

### 4.1 — Criar o projeto Firebase

O Firebase é uma camada sobre o GCP. Precisamos vinculá-lo ao projeto GCP
que criamos.

1. Acesse: https://console.firebase.google.com
2. Clique em **Add project**
3. Selecione o projeto GCP que você criou (`alexandria-vector-shelf-mcp`)
4. Clique em **Continue**
5. Desabilite Google Analytics (não necessário)
6. Clique em **Add Firebase**
7. Aguarde a criação

---

### 4.2 — Habilitar Firebase Auth

1. No console Firebase, vá em **Build → Authentication**
2. Clique em **Get started**
3. Vá em **Sign-in method**
4. Habilite **Anonymous** → clique no toggle → **Save**

---

### 4.3 — Inicializar o Firebase no projeto local

Na raiz do repositório `alexandria-vector-shelf-mcp`:

```bash
firebase login
firebase use SEU-PROJECT-ID
```

Se der erro "project not found":
```bash
firebase projects:list
# Lista os projetos disponíveis

firebase use --add
# Selecione o projeto na lista interativa
```

---

## PARTE 5 — Preparar a infraestrutura base (pré-Terraform)

Alguns recursos precisam existir antes do Terraform rodar.
O Terraform usa o bucket GCS para guardar seu estado — mas não pode criar
o bucket e usá-lo ao mesmo tempo.

### 5.1 — Criar o bucket de estado do Terraform

```bash
# Substitua SEU-PROJECT-ID pelo seu Project ID real
gcloud storage buckets create gs://SEU-PROJECT-ID-tfstate \
  --location=us-central1 \
  --uniform-bucket-level-access \
  --project=SEU-PROJECT-ID
```

**Verificar:**
```bash
gcloud storage buckets list
# Deve aparecer o bucket gs://SEU-PROJECT-ID-tfstate
```

---

### 5.2 — Criar os secrets no Secret Manager

As chaves de API são armazenadas no Secret Manager, não em arquivos.
O Terraform lê esses secrets e os injeta no Cloud Run.

```bash
# Habilitar o Secret Manager API primeiro
gcloud services enable secretmanager.googleapis.com --project=SEU-PROJECT-ID

# Criar o secret para OpenAI
echo -n "sk-sua-chave-openai-aqui" | gcloud secrets create openai-api-key \
  --data-file=- \
  --project=SEU-PROJECT-ID

# Criar o secret para Gemini
echo -n "sua-chave-gemini-aqui" | gcloud secrets create gemini-api-key \
  --data-file=- \
  --project=SEU-PROJECT-ID
```

> Onde obter as chaves:
> - OpenAI: https://platform.openai.com/api-keys
> - Gemini: https://aistudio.google.com/apikey

**Verificar:**
```bash
gcloud secrets list --project=SEU-PROJECT-ID
# Deve listar: openai-api-key, gemini-api-key
```

---

### 5.3 — Criar o Artifact Registry (repositório de imagens Docker)

O Cloud Run precisa de imagens Docker. O Artifact Registry é onde elas ficam.

```bash
gcloud services enable artifactregistry.googleapis.com --project=SEU-PROJECT-ID

gcloud artifacts repositories create alexandria \
  --repository-format=docker \
  --location=us-central1 \
  --description="Docker images for alexandria-vector-shelf-mcp" \
  --project=SEU-PROJECT-ID
```

---

### 5.4 — Fazer o build e push das imagens Docker

O Terraform precisa de imagens Docker existentes para criar os Cloud Run services.
Vamos criar imagens placeholder por agora.

```bash
# Autenticar o Docker com o Artifact Registry
gcloud auth configure-docker us-central1-docker.pkg.dev

# Na raiz do repositório, buildar a imagem de ingestão
docker build -t us-central1-docker.pkg.dev/SEU-PROJECT-ID/alexandria/ingestion:latest \
  -f ingestion/Dockerfile .

# Push para o Artifact Registry
docker push us-central1-docker.pkg.dev/SEU-PROJECT-ID/alexandria/ingestion:latest

# Buildar e fazer push da imagem do chat
docker build -t us-central1-docker.pkg.dev/SEU-PROJECT-ID/alexandria/chat:latest \
  -f chat/Dockerfile .

docker push us-central1-docker.pkg.dev/SEU-PROJECT-ID/alexandria/chat:latest
```

> Se o Dockerfile ainda não existir (você está na Fase 1), crie uma imagem
> placeholder temporária:
> ```bash
> # Cria um Dockerfile mínimo temporário
> echo "FROM python:3.11-slim
> CMD [\"python\", \"-c\", \"print('placeholder')\"]" > /tmp/Dockerfile.placeholder
>
> docker build -t us-central1-docker.pkg.dev/SEU-PROJECT-ID/alexandria/ingestion:latest \
>   -f /tmp/Dockerfile.placeholder .
> docker push us-central1-docker.pkg.dev/SEU-PROJECT-ID/alexandria/ingestion:latest
>
> docker tag us-central1-docker.pkg.dev/SEU-PROJECT-ID/alexandria/ingestion:latest \
>   us-central1-docker.pkg.dev/SEU-PROJECT-ID/alexandria/chat:latest
> docker push us-central1-docker.pkg.dev/SEU-PROJECT-ID/alexandria/chat:latest
> ```

---

## PARTE 6 — Configurar o Terraform

### 6.1 — Atualizar o arquivo dev.tfvars

Abra `infra/environments/dev.tfvars` e substitua os valores:

```hcl
project_id  = "SEU-PROJECT-ID"   # ← seu Project ID real
region      = "us-central1"
environment = "dev"

ingestion_image = "us-central1-docker.pkg.dev/SEU-PROJECT-ID/alexandria/ingestion:latest"
chat_image      = "us-central1-docker.pkg.dev/SEU-PROJECT-ID/alexandria/chat:latest"

chunk_size      = 500
chunk_overlap   = 50
retrieval_top_k = 5
```

---

### 6.2 — Atualizar o backend no main.tf

Abra `infra/main.tf` e atualize o nome do bucket de estado:

```hcl
backend "gcs" {
  bucket = "SEU-PROJECT-ID-tfstate"  # ← substitua aqui
  prefix = "terraform/state"
}
```

---

## PARTE 7 — Rodar o Terraform

### 7.1 — Entrar na pasta infra

```bash
cd infra/
```

---

### 7.2 — Inicializar o Terraform

```bash
terraform init
```

Este comando:
- Baixa os providers do GCP (~50MB)
- Conecta ao bucket de estado no GCS
- Prepara o ambiente local

**Output esperado:**
```
Initializing the backend...
Initializing provider plugins...
- Finding hashicorp/google versions matching "~> 5.0"...
- Installing hashicorp/google v5.x.x...
Terraform has been successfully initialized!
```

Se aparecer erro de bucket não encontrado, volte ao passo 5.1.

---

### 7.3 — Validar a configuração

```bash
terraform validate
```

**Output esperado:**
```
Success! The configuration is valid.
```

Se aparecer erros de sintaxe, corrija os arquivos `.tf` apontados.

---

### 7.4 — Ver o plano de execução

```bash
terraform plan -var-file="environments/dev.tfvars"
```

Este comando mostra EXATAMENTE o que o Terraform vai criar, modificar
ou destruir — sem fazer nada ainda. Leia com atenção.

**Output esperado (resumo):**
```
Plan: 18 to add, 0 to change, 0 to destroy.

Changes to be made:
  + google_project_service.apis["run.googleapis.com"]
  + google_project_service.apis["firestore.googleapis.com"]
  + google_service_account.ingestion
  + google_service_account.chat
  + google_storage_bucket.epubs
  + google_firestore_database.main
  + google_firestore_index.chunks_vector
  + google_cloud_run_v2_service.ingestion
  + google_cloud_run_v2_service.chat
  ...
```

> ℹ️ O sinal `+` significa "vai criar". `-` significa "vai destruir".
> `~` significa "vai modificar". Nunca rode `apply` sem ler o `plan` primeiro.

---

### 7.5 — Aplicar a infraestrutura

```bash
terraform apply -var-file="environments/dev.tfvars"
```

O Terraform vai mostrar o plano novamente e perguntar:
```
Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value:
```

Digite `yes` e pressione Enter.

**Tempo estimado:** 5–10 minutos.

O Terraform vai criar os recursos em ordem, respeitando as dependências.

**Output final esperado:**
```
Apply complete! Resources: 18 added, 0 changed, 0 destroyed.

Outputs:

ingestion_service_url = "https://alexandria-ingestion-dev-xxxx-uc.a.run.app"
chat_service_url      = "https://alexandria-chat-dev-xxxx-uc.a.run.app"
epub_bucket_name      = "SEU-PROJECT-ID-epubs-dev"
next_steps = <<EOT
  ✅ Infrastructure deployed successfully.
  ...
EOT
```

---

## PARTE 8 — Pós-deploy: configurações manuais

O Terraform fez a maior parte do trabalho. Agora as configurações que
ficaram fora do Terraform.

### 8.1 — Criar o Firestore vector index

O índice vetorial não é criado pelo Terraform automaticamente em todos
os casos. Execute:

```bash
gcloud firestore indexes composite create \
  --collection-group=chunks \
  --query-scope=COLLECTION \
  --field-config=order=ASCENDING,field-path="book_id" \
  --field-config=field-path="embedding",vector-config='{"dimension":"1536","flat":"{}"}' \
  --database="(default)" \
  --project=SEU-PROJECT-ID
```

Verificar status (aguarde READY, leva 5–15 minutos):
```bash
gcloud firestore indexes composite list --project=SEU-PROJECT-ID
```

---

### 8.2 — Criar o arquivo firestore.rules

Na raiz do repositório, crie `firestore.rules`:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId} {
      allow read, write: if request.auth != null
                         && request.auth.uid == userId;
    }
    match /books/{bookId} {
      allow read, write: if request.auth != null
                         && request.auth.uid == resource.data.user_id;
      allow create: if request.auth != null
                    && request.auth.uid == request.resource.data.user_id;
    }
    match /chunks/{chunkId} {
      allow read: if request.auth != null
                  && request.auth.uid == resource.data.user_id;
      allow write: if false;
    }
  }
}
```

Criar também `storage.rules`:

```javascript
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /epubs/{userId}/{allPaths=**} {
      allow read, write: if request.auth != null
                         && request.auth.uid == userId;
    }
  }
}
```

Criar `firebase.json` na raiz:

```json
{
  "firestore": {
    "rules": "firestore.rules"
  },
  "storage": {
    "rules": "storage.rules"
  }
}
```

Deploy das regras:
```bash
firebase deploy --only firestore:rules,storage
```

---

### 8.3 — Atualizar o .env com os valores do Terraform

```bash
# Ver os outputs do Terraform
cd infra/
terraform output
```

Copie os valores para o `.env` na raiz do projeto:

```bash
GOOGLE_CLOUD_PROJECT=SEU-PROJECT-ID
FIREBASE_STORAGE_BUCKET=SEU-PROJECT-ID-epubs-dev
INGESTION_SERVICE_URL=https://alexandria-ingestion-dev-xxxx-uc.a.run.app
CHAT_SERVICE_URL=https://alexandria-chat-dev-xxxx-uc.a.run.app
```

---

## PARTE 9 — Verificar se tudo está funcionando

### 9.1 — Testar o ingestion service

```bash
curl -X POST https://alexandria-ingestion-dev-xxxx-uc.a.run.app/health
# Deve retornar: {"status": "ok"}
```

### 9.2 — Testar o chat service

```bash
curl https://alexandria-chat-dev-xxxx-uc.a.run.app/health
# Deve retornar: {"status": "ok"}
```

### 9.3 — Ver os logs do Cloud Run

```bash
# Logs do ingestion service
gcloud run services logs read alexandria-ingestion-dev \
  --region=us-central1 \
  --project=SEU-PROJECT-ID

# Logs do chat service
gcloud run services logs read alexandria-chat-dev \
  --region=us-central1 \
  --project=SEU-PROJECT-ID
```

### 9.4 — Ver os recursos no console GCP

Acesse https://console.cloud.google.com e verifique:

- **Cloud Run** → dois serviços: `alexandria-ingestion-dev` e `alexandria-chat-dev`
- **Firestore** → database `(default)` com as collections
- **Cloud Storage** → bucket `SEU-PROJECT-ID-epubs-dev`
- **IAM** → service accounts `alexandria-ingestion` e `alexandria-chat`

---

## PARTE 10 — Comandos do dia a dia

```bash
# Ver o estado atual da infra
terraform show

# Ver os outputs (URLs dos serviços)
terraform output

# Atualizar a imagem Docker do ingestion service
docker build -t us-central1-docker.pkg.dev/SEU-PROJECT-ID/alexandria/ingestion:latest \
  -f ingestion/Dockerfile .
docker push us-central1-docker.pkg.dev/SEU-PROJECT-ID/alexandria/ingestion:latest
terraform apply -var-file="environments/dev.tfvars"  # re-deploya com nova imagem

# Destruir tudo (cuidado!)
terraform destroy -var-file="environments/dev.tfvars"

# Ver o custo estimado (instale o infracost)
brew install infracost
infracost breakdown --path .
```

---

## Troubleshooting — Erros comuns

### "Error: googleapi: Error 403: The caller does not have permission"

Você não está autenticado ou o projeto não está configurado.

```bash
gcloud auth application-default login
gcloud config set project SEU-PROJECT-ID
```

---

### "Error: Failed to get existing workspaces: querying Cloud Storage failed"

O bucket de estado não existe ou o nome está errado.

```bash
# Verificar se o bucket existe
gcloud storage buckets list | grep tfstate

# Se não existir, criar:
gcloud storage buckets create gs://SEU-PROJECT-ID-tfstate \
  --location=us-central1
```

---

### "Error: Error waiting for Cloud Run Service to be created: timeout"

O Cloud Run demora para criar na primeira vez. Rode novamente:

```bash
terraform apply -var-file="environments/dev.tfvars"
```

O Terraform é idempotente — rodar duas vezes não cria recursos duplicados.

---

### "Error: Secret Manager secret not found"

Os secrets não foram criados no passo 5.2.

```bash
echo -n "sua-chave" | gcloud secrets create openai-api-key --data-file=-
```

---

### O Terraform travou no meio

Ctrl+C para cancelar. Depois:

```bash
terraform refresh -var-file="environments/dev.tfvars"
terraform apply -var-file="environments/dev.tfvars"
```

---

## Resumo dos comandos em ordem

```bash
# 1. Instalar ferramentas
brew install google-cloud-sdk terraform
npm install -g firebase-tools

# 2. Autenticar
gcloud auth login
gcloud auth application-default login
gcloud config set project SEU-PROJECT-ID
firebase login

# 3. Criar recursos pré-Terraform
gcloud storage buckets create gs://SEU-PROJECT-ID-tfstate --location=us-central1
gcloud secrets create openai-api-key --data-file=- <<< "sk-..."
gcloud secrets create gemini-api-key --data-file=- <<< "sua-chave"

# 4. Build e push das imagens
gcloud auth configure-docker us-central1-docker.pkg.dev
docker build -t us-central1-docker.pkg.dev/SEU-PROJECT-ID/alexandria/ingestion:latest -f ingestion/Dockerfile .
docker push us-central1-docker.pkg.dev/SEU-PROJECT-ID/alexandria/ingestion:latest
docker build -t us-central1-docker.pkg.dev/SEU-PROJECT-ID/alexandria/chat:latest -f chat/Dockerfile .
docker push us-central1-docker.pkg.dev/SEU-PROJECT-ID/alexandria/chat:latest

# 5. Rodar o Terraform
cd infra/
terraform init
terraform validate
terraform plan -var-file="environments/dev.tfvars"
terraform apply -var-file="environments/dev.tfvars"

# 6. Deploy das Firebase rules
cd ..
firebase deploy --only firestore:rules,storage
```
