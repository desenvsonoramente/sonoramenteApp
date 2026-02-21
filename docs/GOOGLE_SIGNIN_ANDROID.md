# Login com Google no Android – Erro DEVELOPER_ERROR

Se ao entrar com Google aparecer erro ou a tela não concluir o login, normalmente é **configuração no Firebase/Google Cloud**, não bug no código.

## O que fazer

### 1. Obter a impressão digital SHA-1 do app

No terminal, na pasta do projeto (onde está a pasta `android`), rode:

**Windows (PowerShell ou CMD):**
```bash
cd android
.\gradlew signingReport
```

**macOS/Linux:**
```bash
cd android
./gradlew signingReport
```

Na saída, procure por **SHA1** (e, se quiser, **SHA256**) em `Variant: debug` e/ou `release`. Exemplo:
```
Variant: debug
Config: debug
Store: C:\Users\...\.android\debug.keystore
Alias: AndroidDebugKey
SHA1: AA:BB:CC:...
SHA-256: 11:22:33:...
```

- Para **testar no celular/emulador**: use o SHA1 do **debug**.
- Para **app publicado**: use o SHA1 do **release** (do seu `key.properties`).

### 2. Cadastrar no Firebase Console

1. Acesse [Firebase Console](https://console.firebase.google.com/) e abra o projeto do app.
2. Ícone de **engrenagem** → **Configurações do projeto**.
3. Em **Seus aplicativos**, selecione o app **Android** (pacote `com.sonoramente.app`).
4. Role até **Impressões digitais do certificado SHA**.
5. Clique em **Adicionar impressão digital**, cole o **SHA-1** (e opcionalmente SHA-256) e salve.

### 3. Ativar “Entrar com Google” no Authentication

1. No Firebase: **Authentication** → **Sign-in method**.
2. Ative o provedor **Google** e salve.

### 4. Google Cloud (se ainda falhar)

1. No Firebase, em **Configurações do projeto** → **Geral**, abra o link do **Projeto do Google Cloud**.
2. Em **APIs e serviços** → **Credenciais**, confira se existe um **Cliente OAuth 2.0** do tipo **Android** com:
   - **Nome do pacote**: `com.sonoramente.app`
   - **Impressão digital do certificado SHA-1**: a mesma que você colocou no Firebase.

Se não existir, crie um cliente Android com esse pacote e SHA-1.

---

Depois de salvar o SHA-1 no Firebase e ativar o Google no Authentication, **reinstale o app** no dispositivo (ou desinstale e instale de novo) e tente entrar com Google outra vez.
