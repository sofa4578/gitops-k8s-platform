# `gitops-k8s-platform` — повний блюпринт реалізації

Проєкт A портфоліо. Внутрішня платформа на Kubernetes, керована повністю через GitOps.

**Мова артефактів:** усе, що потрапляє в репозиторій (README, коментарі в коді, commit-меседжі, назви файлів, документація в `docs/`), пишеться **англійською**. Цей документ — робочий план для тебе, він українською.

---

## 1. Назва проєкту

```
gitops-k8s-platform
```

Альтернативи, якщо хочеш інший акцент:
- `k8s-platform-gitops` — те саме, інший порядок слів
- `argocd-platform-blueprint` — акцент на Argo CD
- `multi-tenant-k8s-platform` — акцент на мультитенантності

Я рекомендую перший. Він містить два ключових слова, за якими рекрутери і ATS шукають (`gitops`, `k8s`), і слово `platform`, яке сигналізує, що це не деплой одного застосунку.

---

## 2. Концепція проєкту

### Що робить система

Git-репозиторій є єдиним джерелом істини для стану Kubernetes-кластера. Argo CD, розгорнутий у кластері, безперервно порівнює фактичний стан кластера з тим, що описано в Git, і приводить кластер до відповідності.

Репозиторій описує:

1. **Платформний шар** — ingress-контролер, менеджер TLS-сертифікатів, контролер секретів, metrics-server. Це те, що надає команди розробки, а не те, що вони пишуть самі.
2. **Тенантський шар** — два ізольовані namespace (`team-alpha`, `team-beta`), кожен зі своїми RBAC-правами, мережевими політиками, квотами ресурсів і власним екземпляром застосунку.
3. **Застосунковий шар** — Helm-чарт, який ти пишеш сама, параметризований під два середовища (`dev`, `prod`).

Розробник змінює версію образу в файлі значень через pull request. Після мержу Argo CD протягом хвилини приводить кластер у новий стан. Ручна зміна через `kubectl` відкочується автоматично.

### Яку реальну проблему це вирішує

**Дрейф конфігурації.** У кластерах, куди люди ходять руками, через півроку ніхто не може відповісти, чому певний Deployment має саме такі налаштування. Немає історії, немає автора, немає можливості відтворити стан. GitOps робить кожну зміну комітом: з автором, датою, ревʼю і можливістю відкату одним `git revert`.

**Розподіл прав.** У push-моделі CD (коли пайплайн робить `kubectl apply`) система CI має креденшели кластера. Компрометація CI = компрометація кластера. У pull-моделі кластер сам тягне зміни, і його креденшели ніколи не залишають кластер.

**Онбординг нової команди.** Додати новий тенант — це один каталог і один pull request, а не тижневе листування з платформною командою.

### Хто таке використовує

Будь-яка компанія з платформною або SRE-функцією і більш ніж одним середовищем. Це стандартна форма організації в командах від приблизно 20 інженерів. Argo CD — проєкт CNCF рівня Graduated, і він фігурує у значній частині вакансій DevOps на українському ринку.

### Чому це сильніше за типовий джуніорський проєкт

«Простий Kubernetes-деплой» доводить, що ти вмієш застосувати маніфест. Цей проєкт доводить, що ти розумієш:

- різницю між **декларативним бажаним станом** і **імперативною командою**;
- механіку **реконсиляції** і чому вона важлива;
- **мультитенантність** та ізоляцію на рівні мережі, прав і ресурсів;
- **написання** Helm-чартів, а не лише їх встановлення;
- **життєвий цикл TLS-сертифікатів**;
- **правильну форму зберігання секретів у Git**;
- **промоушен між середовищами** через pull request.

Демонстрація відкату дрейфу (ти вручну масштабуєш Deployment, Argo CD за 30 секунд повертає його назад) — це те, чого немає майже в жодному джуніорському портфоліо, і це один скріншот.

---

## 3. Навички, які доводить проєкт

**Infrastructure**
Декларативне керування інфраструктурою, ідемпотентність, bootstrap-послідовність, розділення платформного і застосункового шарів.

**CI/CD**
Багатоетапні GitHub Actions пайплайни, розділення CI (валідація, збірка) і CD (реконсиляція), автоматизоване створення PR для промоушену версій, matrix-стратегії, кешування, required status checks.

**Containers**
Multi-stage Dockerfile, non-root користувач, read-only root filesystem, пінінг базового образу за digest, `.dockerignore`, сканування Trivy, тегування за commit SHA.

**Kubernetes**
Namespaces, Deployment, Service, Ingress, ConfigMap, Secret, ServiceAccount, HPA, PodDisruptionBudget, ResourceQuota, LimitRange, RBAC (Role, RoleBinding, ClusterRole), NetworkPolicy, Pod Security Admission, probes, resource requests/limits, sync waves, CRD.

**Cloud**
Опційно: k3s на VM, Cloudflare DNS та Let's Encrypt DNS-01, керування вартістю.

**Security**
Sealed Secrets, шифрування секретів у Git, RBAC з мінімальними правами, default-deny NetworkPolicy, non-root контейнери, сканування образів (Trivy), сканування репозиторію на секрети (gitleaks), сканування маніфестів на політики (kubeconform + policy checks), branch protection.

**Monitoring**
Базовий health-моніторинг платформи, Argo CD Application health status, metrics-server і HPA. Повна обсервабельність — це Проєкт C, тут навмисно мінімум.

**Networking**
Ingress і маршрутизація за hostname, TLS-термінація, ClusterIP проти LoadBalancer, DNS усередині кластера, NetworkPolicy на рівні L3/L4, port-mapping у kind.

**Automation**
Bootstrap одною командою, Makefile як інтерфейс, скрипти шифрування секретів, автоматичний PR для bump версії образу, app-of-apps як механізм самозастосування.

**Reliability**
Self-healing і автоматична реконсиляція, PDB, rolling update із `maxUnavailable: 0`, HPA, sync waves для коректного порядку розгортання, відкат через `git revert`.

**Documentation**
ADR (architecture decision records), діаграма архітектури, runbook з траблшутингу, документований процес промоушену.

---

## 4. Архітектура

### Компоненти

| Компонент | Namespace | Роль |
|---|---|---|
| kind / k3s | — | Кластер Kubernetes |
| Argo CD | `argocd` | Двигун реконсиляції, керує собою і всім іншим |
| ingress-nginx | `ingress-nginx` | Точка входу HTTP/HTTPS, маршрутизація за hostname |
| cert-manager | `cert-manager` | Випуск і оновлення TLS-сертифікатів |
| sealed-secrets | `kube-system` | Розшифрування SealedSecret → Secret усередині кластера |
| metrics-server | `kube-system` | Метрики CPU/memory для HPA |
| kube-prometheus-stack (мінімальний) | `monitoring` | Health платформи, підготовка ґрунту для Проєкту C |
| webapp (tenant alpha) | `team-alpha` | Застосунок, розгорнутий із власного Helm-чарта |
| webapp (tenant beta) | `team-beta` | Той самий чарт, інші значення |

### Комунікація між компонентами

```
Розробник відкриває PR
        │
        ▼
GitHub Actions (ci-manifests.yml)
        │  yamllint → helm lint → helm template → kubeconform → policy checks
        │  всі перевірки обовʼязкові, мерж заблокований до їх проходження
        ▼
Мерж у main
        │
        ▼
Argo CD (repo-server) опитує Git кожні 3 хв
        │  або миттєво через webhook
        ▼
Argo CD (application-controller) порівнює desired vs live
        │
        ▼
Argo CD застосовує diff до Kubernetes API
        │
        ▼
Kubernetes створює/оновлює обʼєкти
```

Окремий потік для коду застосунку:

```
Push у src/webapp/**
        │
        ▼
GitHub Actions (ci-app.yml)
        │  ruff → pytest → docker build → Trivy scan → push у GHCR
        ▼
GitHub Actions (promote.yml)
        │  відкриває PR, що змінює image.tag у envs/dev/team-alpha-values.yaml
        ▼
Ревʼю і мерж → Argo CD синхронізує dev
        │
        ▼
Ручний PR, що копіює той самий tag у envs/prod/ → Argo CD синхронізує prod
```

### Мережевий потік

```
Браузер
   │ https://alpha.platform.local
   ▼
kind extraPortMappings (host :443 → node :443)
   │
   ▼
ingress-nginx Service (NodePort 30443 / hostPort)
   │
   ▼
ingress-nginx Controller Pod
   │  TLS-термінація сертифікатом від cert-manager
   │  маршрутизація за Host-заголовком
   ▼
Service webapp (ClusterIP) у namespace team-alpha
   │
   ▼
Endpoints → Pod webapp
```

NetworkPolicy у кожному тенантському namespace: default-deny на ingress і egress, далі явні дозволи:
- ingress: тільки з namespace `ingress-nginx`
- egress: DNS до `kube-system` (порт 53 UDP/TCP), HTTPS назовні (443), заборонено все інше
- **явна заборона** трафіку між `team-alpha` і `team-beta`

### Потік розгортання (bootstrap)

Порядок критичний, бо CRD мають існувати раніше за ресурси, які на них посилаються.

```
Wave -2:  namespaces
Wave -1:  sealed-secrets controller, cert-manager (разом із CRD)
Wave  0:  ingress-nginx, metrics-server
Wave  1:  ClusterIssuer (потребує CRD cert-manager із wave -1)
Wave  2:  AppProject + RBAC + ResourceQuota + NetworkPolicy тенантів
Wave  3:  webapp Applications
```

Argo CD реалізує це через анотацію `argocd.argoproj.io/sync-wave`.

### Потік архітектури (текстова діаграма для README)

```
                        Developer
                            │
                     git push / PR
                            │
                            ▼
                    ┌───────────────┐
                    │    GitHub     │
                    │  (Git = SoT)  │
                    └───────┬───────┘
                            │
             ┌──────────────┴──────────────┐
             │                             │
             ▼                             ▼
    ┌─────────────────┐          ┌──────────────────┐
    │ GitHub Actions  │          │     Argo CD      │
    │   (CI only)     │          │  (pull-based CD) │
    │                 │          │                  │
    │ lint, test,     │          │  poll every 3m   │
    │ build, scan,    │          │  reconcile loop  │
    │ push image      │          │  self-heal: on   │
    └────────┬────────┘          └────────┬─────────┘
             │                            │
             ▼                            │
    ┌─────────────────┐                   │
    │      GHCR       │                   │
    │ (image registry)│                   │
    └────────┬────────┘                   │
             │                            │
             │        ┌───────────────────┘
             │        │
             ▼        ▼
    ┌──────────────────────────────────────────────┐
    │           Kubernetes cluster (kind)          │
    │                                              │
    │  ns: argocd          → Argo CD               │
    │  ns: ingress-nginx   → Ingress Controller    │
    │  ns: cert-manager    → cert-manager          │
    │  ns: kube-system     → sealed-secrets        │
    │                        metrics-server        │
    │  ns: monitoring      → Prometheus (minimal)  │
    │                                              │
    │  ns: team-alpha ─┐                           │
    │    webapp        │  NetworkPolicy: deny-all  │
    │    HPA, PDB      │  ResourceQuota            │
    │    Ingress       │  RBAC: namespace-scoped   │
    │                  │                           │
    │  ns: team-beta ──┘  (ізольовані один від     │
    │    webapp            одного)                 │
    └──────────────────────────────────────────────┘
```

### Пояснення кожного зʼєднання

- **Developer → GitHub.** Єдиний спосіб змінити стан кластера. Прямий доступ `kubectl` існує тільки для читання і діагностики.
- **GitHub → GitHub Actions.** CI не має доступу до кластера взагалі. Це навмисно: у нього немає kubeconfig, немає токенів, немає ServiceAccount. Він тільки валідує і збирає образи.
- **GitHub Actions → GHCR.** Автентифікація через вбудований `GITHUB_TOKEN` з правом `packages: write`. Жодних довготривалих креденшелів.
- **Argo CD → GitHub.** Argo CD читає репозиторій. Для публічного репозиторію — анонімно, без токена взагалі. Це найменша можлива поверхня атаки.
- **Argo CD → Kubernetes API.** Через ServiceAccount усередині кластера. Права обмежені через AppProject: кожен тенантський Application може створювати ресурси тільки у своєму namespace і тільки дозволених типів.
- **ingress-nginx → webapp Service.** Через ClusterIP, дозволений явною NetworkPolicy.
- **cert-manager → Let's Encrypt** (тільки у публічному варіанті). Локально використовується самопідписаний ClusterIssuer, зовнішніх викликів немає.

### Межі безпеки

1. **CI не має доступу до кластера.** Це головна межа. Компрометація GitHub Actions не дає доступу до Kubernetes.
2. **Кожен тенант ізольований** на трьох рівнях: RBAC (хто може що), NetworkPolicy (хто з ким говорить), ResourceQuota (скільки може спожити).
3. **Секрети зашифровані в Git.** Приватний ключ існує тільки всередині кластера, у контролері sealed-secrets. Розшифрувати вміст репозиторію поза кластером неможливо.
4. **Pod Security Admission** у режимі `restricted` на тенантських namespace: заборонені privileged-контейнери, hostNetwork, hostPath, запуск від root.

### Керування секретами

Секрети комітяться у Git у вигляді ресурсів `SealedSecret`. Це асиметричне шифрування: публічним ключем шифруєш локально, приватний ключ ніколи не залишає кластер. Зашифрований секрет привʼязаний до конкретної пари namespace+name, тому його не можна перенести в інший namespace, щоб прочитати.

Процес:
```bash
kubectl create secret generic app-secrets \
  --from-literal=API_KEY=... --dry-run=client -o yaml \
| kubeseal --format yaml --controller-namespace kube-system \
> tenants/team-alpha/sealed-secret.yaml
```

Обґрунтування вибору — у секції 13 і в ADR `docs/decisions/002-secrets-management.md`.

### Зовнішні сервіси

- **GitHub** — хостинг репозиторію, CI, реєстр образів (GHCR).
- **Cloudflare** (опційно, безкоштовний тариф) — DNS для публічної демонстрації і DNS-01 challenge для Let's Encrypt.
- Більше нічого. Жодних платних сервісів.

---

## 5. Технологічний стек

| Технологія | Призначення | Чому саме вона, а не простіша альтернатива |
|---|---|---|
| **kind** | Локальний кластер Kubernetes | Мінікуб піднімає VM і повільніший; k3d швидший, але kind — офіційний інструмент тестування самого Kubernetes і має найкращу підтримку multi-node та port-mapping. Головне: коштує нуль і працює на ноутбуці. |
| **Argo CD** | Pull-based CD, реконсиляція | Альтернатива — `kubectl apply` у GitHub Actions. Вона простіша, але вимагає зберігати kubeconfig у CI, не виявляє дрейф і не має UI зі станом усіх застосунків. Flux — рівноцінна альтернатива, Argo обрано через UI (важливо для скріншотів у портфоліо) і ширшу присутність у вакансіях. |
| **Helm** | Шаблонізація і пакування застосунку | Альтернатива — Kustomize. Kustomize простіший для оверлеїв, але не дає версіонування пакета, `values.schema.json` валідації та умовної логіки. Тут потрібен саме чарт, бо ціль — довести вміння **писати** чарт, а не лише накладати патчі. Kustomize використовується для bootstrap Argo CD, де Helm надлишковий. |
| **ingress-nginx** | HTTP-маршрутизація, TLS-термінація | Альтернатива — Service типу LoadBalancer на кожен застосунок. Це витратно в хмарі (окремий LB на сервіс) і не дає маршрутизації за hostname чи шляхом. Traefik — рівноцінний, ingress-nginx обрано через поширеність. |
| **cert-manager** | Життєвий цикл TLS-сертифікатів | Альтернатива — згенерувати сертифікат вручну і покласти в Secret. Він протухне через 90 днів і ніхто не дізнається. cert-manager перевипускає автоматично і є де-факто стандартом. |
| **Sealed Secrets** | Секрети в Git | Альтернатива — SOPS + ksops-плагін до Argo CD, або External Secrets Operator із хмарним сховищем. Порівняння в ADR-002. Обрано за те, що це єдиний варіант без Argo CD плагінів і без зовнішньої залежності. |
| **metrics-server** | Метрики для HPA | HPA без нього не працює взагалі. У kind не встановлений за замовчуванням. |
| **GitHub Actions** | CI: валідація, тести, збірка, сканування | Вбудований у GitHub, безкоштовний для публічних репозиторіїв, не потребує окремого сервера. Jenkins тут був би окремим проєктом підтримки без нової вигоди. |
| **GHCR** | Реєстр образів | Безкоштовний для публічних образів, автентифікація через `GITHUB_TOKEN` без окремих креденшелів. Docker Hub має ліміти на pull. |
| **Trivy** | Сканування образів і маніфестів | Безкоштовний, швидкий, один бінарник, є офіційний GitHub Action. Snyk потребує акаунт і має ліміти. |
| **kubeconform** | Валідація маніфестів проти схеми Kubernetes | Швидший за `kubeval` (який більше не підтримується) і працює офлайн зі схемами CRD. |
| **gitleaks** | Сканування на секрети | Прямо адресує проблему, яка вже траплялася в твоєму `iac-deploy-pipeline`. |
| **FastAPI** | Тестовий застосунок | Ти вже знаєш його з дипломної. Час на застосунок треба звести до мінімуму — цінність проєкту в платформі, а не в застосунку. |

**Свідомо не використано:** Terraform (кластер локальний, немає хмарних ресурсів для описування — Terraform це Проєкт B), Vault (правильне розгортання з HA і unsealing — окремий проєкт, а погано розгорнутий Vault гірший за його відсутність), Loki/ELK (обсервабельність — Проєкт C), Jenkins, SonarQube, Ansible.

---

## 6. Повна структура репозиторію

```text
gitops-k8s-platform/
├── README.md                          # головний документ, див. секцію 17
├── LICENSE                            # MIT
├── CHANGELOG.md                       # Keep a Changelog формат
├── Makefile                           # єдиний інтерфейс: make up, make bootstrap, make test
├── .gitignore
├── .yamllint.yaml                      # правила лінтингу YAML
├── .gitleaks.toml                      # конфігурація сканера секретів
│
├── docs/
│   ├── architecture.md                # діаграми, потоки, межі безпеки
│   ├── bootstrap.md                   # як підняти з нуля, покроково
│   ├── promotion.md                   # як версія рухається dev → prod
│   ├── security.md                    # модель загроз і контролі
│   ├── troubleshooting.md             # runbook, див. секцію 16
│   ├── images/                        # скріншоти та діаграми для README
│   └── decisions/                     # ADR — architecture decision records
│       ├── 001-pull-based-cd.md
│       ├── 002-secrets-management.md
│       ├── 003-single-repo-vs-split.md
│       └── 004-helm-vs-kustomize.md
│
├── kind/
│   └── cluster.yaml                   # конфіг кластера: 1 control-plane + 2 worker, port mappings
│
├── bootstrap/                         # те, що застосовується руками ОДИН раз
│   ├── argocd/
│   │   ├── kustomization.yaml         # Argo CD з офіційного маніфесту + патчі
│   │   ├── namespace.yaml
│   │   └── patches/
│   │       └── argocd-cm.yaml         # налаштування: resource tracking, exclusions
│   └── root-app.yaml                  # app-of-apps: єдиний Application, що тягне все інше
│
├── platform/                          # спільні компоненти платформи
│   ├── ingress-nginx/
│   │   └── application.yaml           # Argo Application → офіційний Helm-чарт
│   ├── cert-manager/
│   │   ├── application.yaml
│   │   └── issuers/
│   │       ├── selfsigned.yaml        # для локального середовища
│   │       └── letsencrypt.yaml       # для публічної демонстрації (DNS-01)
│   ├── sealed-secrets/
│   │   └── application.yaml
│   ├── metrics-server/
│   │   └── application.yaml
│   └── monitoring/
│       ├── application.yaml           # kube-prometheus-stack, мінімальні values
│       └── values.yaml
│
├── charts/
│   └── webapp/                        # чарт, який ти пишеш сама
│       ├── Chart.yaml
│       ├── values.yaml                # значення за замовчуванням + коментарі
│       ├── values.schema.json         # JSON Schema — валідація значень
│       ├── .helmignore
│       ├── templates/
│       │   ├── _helpers.tpl           # шаблони імен і лейблів
│       │   ├── serviceaccount.yaml
│       │   ├── deployment.yaml
│       │   ├── service.yaml
│       │   ├── ingress.yaml
│       │   ├── hpa.yaml
│       │   ├── pdb.yaml
│       │   ├── networkpolicy.yaml
│       │   └── NOTES.txt              # що показати після встановлення
│       └── tests/
│           └── deployment_test.yaml   # helm-unittest
│
├── tenants/
│   ├── team-alpha/
│   │   ├── namespace.yaml             # + лейбли Pod Security Admission
│   │   ├── appproject.yaml            # Argo AppProject: межі дозволеного
│   │   ├── rbac.yaml                  # Role + RoleBinding для команди
│   │   ├── resourcequota.yaml
│   │   ├── limitrange.yaml            # дефолтні requests/limits
│   │   ├── networkpolicy.yaml         # default-deny + явні дозволи
│   │   └── applications.yaml          # Argo Applications: dev і prod
│   └── team-beta/
│       └── ... (те саме, інші значення)
│
├── envs/
│   ├── dev/
│   │   ├── team-alpha.yaml            # values-оверлей: 1 репліка, debug-логи
│   │   └── team-beta.yaml
│   └── prod/
│       ├── team-alpha.yaml            # 3 репліки, HPA, суворіші ліміти
│       └── team-beta.yaml
│
├── src/
│   └── webapp/
│       ├── Dockerfile
│       ├── .dockerignore
│       ├── requirements.txt
│       ├── app/
│       │   ├── main.py                # FastAPI: /, /health, /ready, /metrics
│       │   └── __init__.py
│       └── tests/
│           └── test_main.py
│
├── scripts/
│   ├── bootstrap.sh                   # від порожнього ноутбука до працюючої платформи
│   ├── seal-secret.sh                 # обгортка над kubeseal
│   ├── drift-demo.sh                  # демонстрація self-heal
│   ├── verify.sh                      # перевірка, що все здорове
│   └── teardown.sh
│
└── .github/
    ├── workflows/
    │   ├── ci-app.yml                 # код застосунку: lint, test, build, scan, push
    │   ├── ci-manifests.yml           # маніфести: yamllint, helm lint, kubeconform
    │   ├── promote.yml                # автоматичний PR із bump версії образу
    │   └── security.yml               # gitleaks + Trivy filesystem scan, за розкладом
    ├── CODEOWNERS
    └── pull_request_template.md
```

### Призначення кожного каталогу

**`bootstrap/`** — єдине, що застосовується руками. Розділення важливе концептуально: має існувати мінімальний набір, який не може керувати сам собою (Argo CD не може встановити Argo CD). Усе інше після цього керується через Git.

**`platform/`** — компоненти, які надає платформа. Кожен файл — це Argo `Application`, що вказує на офіційний Helm-чарт із зафіксованою версією. Ти не форкаєш чужі чарти, ти декларуєш, яку версію і з якими значеннями встановити.

**`charts/webapp/`** — твій власний чарт. Це ключовий артефакт для співбесіди: перше, що відкриють, якщо захочуть перевірити рівень.

**`tenants/`** — межі. Один каталог = один тенант = один namespace + його політики. Додати тенанта = скопіювати каталог і змінити імена.

**`envs/`** — тільки значення, жодних шаблонів. Це те, що змінюється при промоушені. Розділення `charts/` (як) від `envs/` (з якими параметрами) — це те, що робить промоушен однорядковим diff-ом.

**`src/`** — код застосунку. Навмисно маленький.

---

## 7. Покроковий план реалізації

Оцінка: 4–6 тижнів по 8–10 годин на тиждень. Не поспішай — цінність у документації і в тому, що ти зможеш пояснити.

### Фаза 1 — Ініціалізація репозиторію

**Крок 1.1.** Створи репозиторій на GitHub із назвою `gitops-k8s-platform`, публічний, з README, .gitignore (Node → потім заміниш) і ліцензією MIT.

```bash
git clone https://github.com/sofa4578/gitops-k8s-platform.git
cd gitops-k8s-platform
mkdir -p docs/{images,decisions} kind bootstrap/argocd/patches \
  platform/{ingress-nginx,cert-manager/issuers,sealed-secrets,metrics-server,monitoring} \
  charts/webapp/{templates,tests} \
  tenants/{team-alpha,team-beta} envs/{dev,prod} \
  src/webapp/{app,tests} scripts .github/workflows
```

**Крок 1.2.** Створи `.gitignore`:

```gitignore
*.tgz
charts/**/charts/
.DS_Store
__pycache__/
*.pyc
.venv/
kubeconfig
*.decrypted.yaml
.env
```

Рядок `*.decrypted.yaml` важливий: він гарантує, що розшифрований секрет ніколи не потрапить у коміт випадково.

**Крок 1.3.** Створи `Makefile` — навіть порожній зі скелетом. Він стане інтерфейсом до проєкту.

```makefile
.PHONY: help up bootstrap verify drift-demo down lint test

CLUSTER_NAME ?= gitops-platform

help:  ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

up:  ## Create the kind cluster
	kind create cluster --name $(CLUSTER_NAME) --config kind/cluster.yaml

down:  ## Delete the kind cluster
	kind delete cluster --name $(CLUSTER_NAME)
```

**Крок 1.4.** Перший коміт.

```bash
git add -A && git commit -m "chore: initialize repository structure" && git push
```

**Перевірка:** структура каталогів видна на GitHub. Каталоги без файлів Git не зберігає — додай у кожен порожній `.gitkeep` або просто створюй їх у міру наповнення.

**Типова помилка:** створити всю структуру одним комітом і потім місяць нічого не комітити. Комить дрібно, історія — теж частина портфоліо.

---

### Фаза 2 — Підготовка застосунку

**Крок 2.1.** `src/webapp/app/main.py`. Мінімальний FastAPI із чотирма ендпоінтами.

Що всередині:
- `GET /` — повертає JSON із іменем застосунку, версією, іменем поду (з env `POD_NAME` через downward API) та іменем середовища. Імʼя поду в тілі відповіді дозволяє наочно показати балансування і зміну реплік.
- `GET /health` — liveness. Повертає 200 завжди, поки процес живий.
- `GET /ready` — readiness. Повертає 200 тільки після завершення старту; окремий від liveness навмисно.
- `GET /metrics` — Prometheus-формат через `prometheus-client`, лічильник запитів і гістограма латентності.
- Опційно `GET /crash` і `GET /load` — для демонстрації CrashLoopBackOff і HPA. Захисти їх змінною середовища `ENABLE_CHAOS_ENDPOINTS`, за замовчуванням вимкнено.

**Крок 2.2.** `src/webapp/requirements.txt` — з зафіксованими версіями:

```
fastapi==0.115.0
uvicorn[standard]==0.32.0
prometheus-client==0.21.0
```

**Крок 2.3.** `src/webapp/tests/test_main.py` — три тести: `/health` повертає 200, `/ready` повертає 200, `/` містить очікувані ключі. Через `fastapi.testclient`.

```bash
cd src/webapp && python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt pytest httpx
pytest -q
```

**Очікуваний результат:** `3 passed`.

**Типова помилка:** ліньки писати тести, бо «застосунок тривіальний». Тести потрібні не для застосунку — вони потрібні, щоб у CI був крок `pytest`, і щоб гілка `main` була захищена required check-ом. Без них пайплайн виглядає порожнім.

---

### Фаза 3 — Контейнеризація

**Крок 3.1.** `src/webapp/Dockerfile`. Multi-stage, non-root, віртуальне середовище (не `pip install --user`, бо це ламається при зміні користувача — саме та проблема, на яку ти натрапила в дипломній).

```dockerfile
FROM python:3.12-slim@sha256:<digest> AS builder
WORKDIR /build
COPY requirements.txt .
RUN python -m venv /opt/venv \
 && /opt/venv/bin/pip install --no-cache-dir --upgrade pip \
 && /opt/venv/bin/pip install --no-cache-dir -r requirements.txt

FROM python:3.12-slim@sha256:<digest>
RUN useradd --create-home --uid 10001 --shell /usr/sbin/nologin appuser
COPY --from=builder /opt/venv /opt/venv
WORKDIR /app
COPY --chown=appuser:appuser app/ ./app/
ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1
USER 10001
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

Digest отримуєш так:

```bash
docker pull python:3.12-slim
docker inspect --format='{{index .RepoDigests 0}}' python:3.12-slim
```

**Чому digest, а не тег:** тег `3.12-slim` вказує на різні образи в різний час. Пінінг за digest робить збірку відтворюваною і не дає базовому образу мовчки змінитися. У README поясни, що ціною є ручне оновлення, і що в реальному проєкті це робить Renovate або Dependabot.

**Чому немає `HEALTHCHECK`:** у Kubernetes healthcheck рівня Docker ігнорується — за здоровʼя відповідають probes. У дипломній він у тебе був, це нешкідливо, але надлишково. Про це варто написати в ADR.

**Крок 3.2.** `.dockerignore`:

```
.venv/
__pycache__/
*.pyc
tests/
.pytest_cache/
```

**Крок 3.3.** Збірка і перевірка.

```bash
cd src/webapp
docker build -t webapp:dev .
docker run --rm -p 8000:8000 webapp:dev
curl -s localhost:8000/health
docker run --rm --entrypoint id webapp:dev
```

**Очікуваний результат:** `{"status":"ok"}` і `uid=10001(appuser)`.

**Типова помилка:** `Permission denied` при запуску. Причина — файли скопійовані до створення користувача або без `--chown`. Порядок інструкцій у Dockerfile має значення.

**Крок 3.4.** Скануй локально перед тим, як додавати в CI:

```bash
trivy image --severity HIGH,CRITICAL webapp:dev
```

Якщо базовий образ має вразливості — це нормально і навіть корисно: у README покажеш, як пайплайн їх виявляє.

---

### Фаза 4 — Локальний кластер

**Крок 4.1.** `kind/cluster.yaml`:

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: gitops-platform
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
    extraPortMappings:
      - containerPort: 80
        hostPort: 80
        protocol: TCP
      - containerPort: 443
        hostPort: 443
        protocol: TCP
  - role: worker
  - role: worker
```

**Чому три вузли:** з одним вузлом PodDisruptionBudget і `topologySpreadConstraints` нічого не доводять, а `podAntiAffinity` не спрацює. Два воркери дають мінімум, на якому ці механізми видно.

**Чому `extraPortMappings`:** kind працює в Docker. Без явного пробросу портів ingress-контролер недосяжний з хоста. Це найчастіша причина «ingress не працює» в kind.

**Крок 4.2.**

```bash
make up
kubectl get nodes
kubectl cluster-info --context kind-gitops-platform
```

**Очікуваний результат:** три вузли у стані `Ready` протягом хвилини.

**Типова помилка:** порт 80 або 443 уже зайнятий на хості (наприклад, локальним nginx або Docker Desktop). Симптом: `kind create cluster` падає з `port is already allocated`. Рішення: звільнити порт або змінити `hostPort` на 8080/8443 і відповідно правити URL у документації.

**Крок 4.3.** Додай у `/etc/hosts` (Windows: `C:\Windows\System32\drivers\etc\hosts`):

```
127.0.0.1  argocd.platform.local alpha.platform.local beta.platform.local
```

---

### Фаза 5 — Bootstrap Argo CD

**Крок 5.1.** `bootstrap/argocd/namespace.yaml` — просто namespace `argocd`.

**Крок 5.2.** `bootstrap/argocd/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: argocd
resources:
  - namespace.yaml
  - https://raw.githubusercontent.com/argoproj/argo-cd/v2.13.2/manifests/install.yaml
patches:
  - path: patches/argocd-cm.yaml
```

Версія зафіксована навмисно. Посилання на `stable` означає, що кластер, зібраний завтра, буде іншим.

**Крок 5.3.** Встановлення:

```bash
kubectl apply -k bootstrap/argocd/
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s
```

**Крок 5.4.** Отримати початковий пароль і зайти в UI:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
kubectl -n argocd port-forward svc/argocd-server 8080:443
```

Відкрий `https://localhost:8080`, логін `admin`. Попередження про сертифікат очікуване — Argo CD за замовчуванням має самопідписаний.

**Перевірка:** UI відкривається, список Applications порожній.

**Типова помилка:** `argocd-server` у CrashLoopBackOff на машинах з малою кількістю памʼяті. Argo CD у повній конфігурації потребує близько 2 ГБ. Якщо мало — використай `install.yaml` у core-режимі або підніми ліміти Docker Desktop.

---

### Фаза 6 — App-of-apps і платформний шар

**Крок 6.1.** `bootstrap/root-app.yaml` — єдиний Application, який породжує всі інші:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/sofa4578/gitops-k8s-platform.git
    targetRevision: main
    path: platform
    directory:
      recurse: true
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

`prune: true` — видаляти ресурси, яких більше немає в Git. `selfHeal: true` — відкочувати ручні зміни. Обидва прапорці разом і є GitOps; без них це просто автоматичний деплой.

**Крок 6.2.** Створи Application для кожного платформного компонента. Приклад `platform/ingress-nginx/application.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ingress-nginx
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "0"
spec:
  project: default
  source:
    repoURL: https://kubernetes.github.io/ingress-nginx
    chart: ingress-nginx
    targetRevision: 4.11.3
    helm:
      values: |
        controller:
          hostPort:
            enabled: true
          service:
            type: NodePort
          nodeSelector:
            ingress-ready: "true"
          tolerations:
            - key: node-role.kubernetes.io/control-plane
              operator: Equal
              effect: NoSchedule
  destination:
    server: https://kubernetes.default.svc
    namespace: ingress-nginx
  syncPolicy:
    automated: { prune: true, selfHeal: true }
    syncOptions: [CreateNamespace=true]
```

Аналогічно для `cert-manager` (wave `-1`, з `installCRDs: true`), `sealed-secrets` (wave `-1`), `metrics-server` (wave `0`, з `--kubelet-insecure-tls` для kind).

**Крок 6.3.** Застосуй root:

```bash
kubectl apply -f bootstrap/root-app.yaml
kubectl -n argocd get applications -w
```

**Очікуваний результат:** через 2–4 хвилини всі Applications у стані `Synced` / `Healthy`.

**Типова помилка №1:** `metrics-server` у CrashLoopBackOff у kind. Причина — kubelet використовує самопідписаний сертифікат. Рішення: додати `--kubelet-insecure-tls` у args. Обовʼязково задокументуй, що це прийнятно **тільки** для локального середовища.

**Типова помилка №2:** cert-manager `Application` у стані `OutOfSync` із помилкою про невідомий тип `ClusterIssuer`. Причина — ClusterIssuer застосовується раніше, ніж встановлюються CRD. Рішення — sync waves: cert-manager у wave `-1`, issuers у wave `1`.

**Крок 6.4.** Зроби скріншот UI Argo CD із деревом усіх застосунків. Це головна ілюстрація README.

---

### Фаза 7 — Написання Helm-чарта

Це найважливіша фаза для співбесіди.

**Крок 7.1.** `charts/webapp/Chart.yaml`:

```yaml
apiVersion: v2
name: webapp
description: Generic web application chart used by platform tenants
type: application
version: 0.1.0
appVersion: "0.1.0"
maintainers:
  - name: Sofiia Levko
```

Розрізняй `version` (версія чарта) і `appVersion` (версія застосунку). Це питання на співбесіді.

**Крок 7.2.** `templates/_helpers.tpl` — стандартні хелпери: `webapp.name`, `webapp.fullname`, `webapp.labels` (із рекомендованими лейблами `app.kubernetes.io/*`), `webapp.selectorLabels`.

Ключовий момент: `selectorLabels` **не** мають містити `app.kubernetes.io/version`. Селектор Deployment імутабельний, і якщо версія в ньому — кожен апгрейд версії ламатиме реліз. Це реальна пастка і хороша відповідь на співбесіді.

**Крок 7.3.** `templates/deployment.yaml`. Обовʼязково має містити:

- `replicas` тільки якщо HPA вимкнено (`{{- if not .Values.autoscaling.enabled }}`) — інакше Argo CD і HPA битимуться за поле
- `securityContext` на рівні поду і контейнера: `runAsNonRoot`, `runAsUser: 10001`, `seccompProfile: RuntimeDefault`, `readOnlyRootFilesystem: true`, `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`
- `emptyDir` том на `/tmp`, бо з read-only ФС uvicorn інакше не стартує
- probes: liveness на `/health`, readiness на `/ready`, різні періоди
- `resources` з requests і limits
- `POD_NAME` через downward API
- анотацію з чексумою ConfigMap, щоб зміна конфігу викликала рестарт:
  `checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}`
- `strategy: RollingUpdate` з `maxUnavailable: 0`
- `topologySpreadConstraints` по `kubernetes.io/hostname`

**Крок 7.4.** `templates/hpa.yaml`, `pdb.yaml`, `ingress.yaml`, `service.yaml`, `serviceaccount.yaml`, `networkpolicy.yaml` — усі під умовними прапорцями у values.

**Крок 7.5.** `values.schema.json` — JSON Schema, що вимагає `image.repository`, `image.tag`, забороняє `latest` як тег (через `not: {const: "latest"}`), вимагає, щоб `replicaCount` був цілим ≥ 1.

Це рідкість у джуніорських чартах і сильний сигнал.

**Крок 7.6.** Перевірка:

```bash
helm lint charts/webapp
helm template test charts/webapp | kubeconform -strict -summary -
helm template test charts/webapp -f envs/prod/team-alpha.yaml | less
```

**Очікуваний результат:** `1 chart(s) linted, 0 chart(s) failed`, kubeconform без помилок.

**Крок 7.7.** Юніт-тести чарта:

```bash
helm plugin install https://github.com/helm-unittest/helm-unittest
helm unittest charts/webapp
```

Напиши 4–5 тестів: що `latest` відхиляється схемою, що при `autoscaling.enabled=true` поле `replicas` відсутнє, що securityContext присутній, що ingress не рендериться при `ingress.enabled=false`.

---

### Фаза 8 — Тенанти й ізоляція

**Крок 8.1.** `tenants/team-alpha/namespace.yaml` із лейблами Pod Security Admission:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: team-alpha
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: latest
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

**Крок 8.2.** `resourcequota.yaml` — обмеж `requests.cpu`, `requests.memory`, `limits.cpu`, `limits.memory`, `count/pods`, `count/services.loadbalancers: "0"` (тенанти не мають права створювати LoadBalancer — вхід тільки через платформний ingress).

**Крок 8.3.** `limitrange.yaml` — дефолтні requests/limits, щоб под без явних значень не міг бути створений і не з'їв квоту.

**Крок 8.4.** `networkpolicy.yaml` — три політики:

1. `default-deny-all` — порожній `podSelector`, `policyTypes: [Ingress, Egress]`, жодних правил.
2. `allow-from-ingress-nginx` — ingress із namespace, що має лейбл `kubernetes.io/metadata.name: ingress-nginx`.
3. `allow-dns-egress` — egress на порт 53 UDP і TCP до namespace `kube-system`.

**Найчастіша помилка в усьому проєкті:** застосувати default-deny і забути дозволити DNS. Симптом — поди стартують, але будь-яке звернення за іменем падає з таймаутом, а `nslookup` усередині поду висить. Це обовʼязково має бути в `docs/troubleshooting.md`.

**Крок 8.5.** `appproject.yaml` — Argo AppProject, що обмежує тенанта:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: team-alpha
  namespace: argocd
spec:
  description: Tenant project for team-alpha
  sourceRepos:
    - https://github.com/sofa4578/gitops-k8s-platform.git
  destinations:
    - server: https://kubernetes.default.svc
      namespace: team-alpha
  clusterResourceWhitelist: []          # жодних кластерних ресурсів
  namespaceResourceBlacklist:
    - group: ""
      kind: ResourceQuota
    - group: ""
      kind: LimitRange
```

Це і є «least privilege» у GitOps: навіть якщо хтось закомітить у каталог тенанта ClusterRoleBinding, Argo CD відмовиться його застосувати.

**Крок 8.6.** `applications.yaml` — два Application (dev і prod), кожен вказує на `charts/webapp` із `valueFiles` із `envs/`.

**Перевірка ізоляції:**

```bash
kubectl -n team-alpha run tmp --rm -it --image=curlimages/curl --restart=Never -- \
  curl -m 5 http://webapp.team-beta.svc.cluster.local
```

Очікуваний результат: таймаут. Зроби скріншот — це доказ, що NetworkPolicy працює.

---

### Фаза 9 — Секрети

**Крок 9.1.** Встанови CLI:

```bash
# Linux
KUBESEAL_VERSION=0.27.1
curl -sLo kubeseal.tar.gz \
  "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz"
tar xzf kubeseal.tar.gz kubeseal && sudo install kubeseal /usr/local/bin/
```

**Крок 9.2.** `scripts/seal-secret.sh` — обгортка, яка приймає namespace, імʼя і пари ключ=значення, і виводить SealedSecret.

**Крок 9.3.** Створи секрет для тенанта і закоміть **зашифровану** версію.

**Крок 9.4.** Перевір, що працює:

```bash
kubectl -n team-alpha get secret app-secrets -o jsonpath='{.data}' | head -c 100
```

**Критично важливо задокументувати:** приватний ключ контролера живе в Secret `sealed-secrets-key*` у `kube-system`. Якщо кластер знищити, усі SealedSecret стають нерозшифровуваними. У `docs/security.md` опиши процедуру бекапу цього ключа і те, що в реальному проєкті це найважливіший бекап у системі. Це питання, яке ставлять на співбесіді, і майже ніхто не має відповіді.

---

### Фаза 10 — CI-пайплайни

**Крок 10.1.** `.github/workflows/ci-manifests.yml` — тригер на PR, що зачіпає `charts/**`, `platform/**`, `tenants/**`, `envs/**`.

Джоби: `yamllint` → `helm lint` → `helm unittest` → `helm template | kubeconform -strict` для кожної комбінації env×tenant (matrix) → перевірка політик.

**Крок 10.2.** `.github/workflows/ci-app.yml` — тригер на push у `src/webapp/**`.

Джоби: `ruff check` → `pytest` → `docker/build-push-action` із тегами `ghcr.io/sofa4578/webapp:${{ github.sha }}` і `:sha-short` → `trivy image --exit-code 1 --severity CRITICAL` → push.

Важливо: сканування **до** пушу, і `--exit-code 1` на CRITICAL. Пайплайн, що сканує і ігнорує результат, гірший за відсутність сканування, бо створює хибне відчуття безпеки.

**Крок 10.3.** `.github/workflows/promote.yml` — після успішного `ci-app`, через `peter-evans/create-pull-request`, відкриває PR, що змінює `image.tag` у `envs/dev/*.yaml`.

Ключова деталь: **PR, а не прямий коміт**. Прямий коміт у `main` з CI обходить branch protection і робить пайплайн привілейованим актором. PR зберігає модель «усе через ревʼю».

**Крок 10.4.** `.github/workflows/security.yml` — за розкладом (`cron: '0 6 * * 1'`) плюс на PR: `gitleaks` по всьому репозиторію і `trivy fs` по `src/`.

**Крок 10.5.** Увімкни branch protection: Settings → Branches → `main` → require PR, require status checks (перелічи джоби з `ci-manifests`), require conversation resolution.

**Перевірка:** відкрий PR із навмисною помилкою (наприклад, `image.tag: latest`). Пайплайн має впасти на `values.schema.json` валідації. Зроби скріншот заблокованого мержу.

---

### Фаза 11 — TLS та Ingress

**Крок 11.1.** Локально: `platform/cert-manager/issuers/selfsigned.yaml` — самопідписаний ClusterIssuer плюс CA-сертифікат, від якого підписуються сертифікати тенантів.

**Крок 11.2.** Ingress у чарті з анотацією `cert-manager.io/cluster-issuer` і секцією `tls`.

**Крок 11.3.** Перевірка:

```bash
kubectl -n team-alpha get certificate
kubectl -n team-alpha describe certificate webapp-tls
curl -k https://alpha.platform.local
```

**Очікуваний результат:** `Certificate` у стані `Ready=True`, curl повертає JSON застосунку.

**Типова помилка:** `Certificate` вічно в `Ready=False`. Діагностика послідовна: `describe certificate` → знайти `CertificateRequest` → `describe certificaterequest` → знайти `Order` → `describe order` → `Challenge`. Ланцюжок cert-manager із чотирьох ресурсів — саме те, що треба вміти проходити, і саме те, що варто описати в troubleshooting.

**Крок 11.4 (опційно, публічна демонстрація).** Купи домен (близько $10/рік) або візьми безкоштовний піддомен, направ NS на Cloudflare, підніми k3s на VM за €4/міс у Hetzner, використай Let's Encrypt із DNS-01 через Cloudflare API-токен (зберігається як SealedSecret). Це дає реальний зелений замок на скріншоті.

Альтернатива за нуль грошей: Cloudflare Tunnel до локального kind-кластера. TLS термінується на боці Cloudflare, публічна адреса є, платити не треба.

---

### Фаза 12 — Демонстрація self-heal і відкату

**Крок 12.1.** `scripts/drift-demo.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
echo "Current replicas:"
kubectl -n team-alpha get deploy webapp -o jsonpath='{.spec.replicas}'; echo
echo "Manually scaling to 7 (simulating an out-of-band change)..."
kubectl -n team-alpha scale deploy webapp --replicas=7
echo "Waiting for Argo CD to reconcile..."
for i in $(seq 1 24); do
  R=$(kubectl -n team-alpha get deploy webapp -o jsonpath='{.spec.replicas}')
  echo "  t+${i}0s: replicas=$R"
  [ "$R" != "7" ] && { echo "Reverted by Argo CD."; exit 0; }
  sleep 10
done
echo "Not reverted — check selfHeal setting."; exit 1
```

**Крок 12.2.** Демонстрація відкату версії:

```bash
git revert <sha-of-image-bump> && git push
```

Заміряй час від пушу до того, як у кластері зʼявилася попередня версія. Впиши число в README.

**Крок 12.3.** Зніми обидві демонстрації як GIF (`asciinema` + `agg`, або просто скріншоти до/після). GIF у README — це те, що змушує зупинитися.

---

### Фаза 13 — Документація і фінальна поліровка

**Крок 13.1.** Напиши чотири ADR. Формат кожного: Context / Decision / Alternatives considered / Consequences. По одній сторінці. Це найдешевший спосіб довести «architecture thinking».

**Крок 13.2.** `docs/troubleshooting.md` — усі сценарії з секції 16, у форматі симптоми → команди → причина → рішення.

**Крок 13.3.** Діаграма архітектури. Використай [Excalidraw](https://excalidraw.com) або Mermaid прямо в README (GitHub рендерить Mermaid нативно). Не витрачай на це більше двох годин.

**Крок 13.4.** README за структурою з секції 17.

**Крок 13.5.** Опис репозиторію, топіки, реліз `v1.0.0`, CHANGELOG.

**Крок 13.6.** Перевір фінальний стан:

```bash
make down && make up && ./scripts/bootstrap.sh && ./scripts/verify.sh
```

Це найважливіша перевірка всього проєкту: платформа має підніматися з нуля однією командою. Якщо ні — щось не задокументовано.

---

## 8. Файл за файлом

### `kind/cluster.yaml`
Топологія локального кластера. Три вузли, лейбл `ingress-ready` на control-plane, проброс портів 80/443 на хост.

### `bootstrap/argocd/kustomization.yaml`
Встановлення Argo CD із зафіксованої версії офіційного маніфесту плюс патчі. Kustomize, а не Helm, бо для одноразового bootstrap Helm додає стан (реліз у кластері), який тут не потрібен.

### `bootstrap/root-app.yaml`
Точка входу app-of-apps. Єдиний ресурс, який ти застосовуєш руками після Argo CD. Рекурсивно читає `platform/`. `prune: true` і `selfHeal: true`.

### `platform/*/application.yaml`
Кожен — Argo `Application` на офіційний чарт із зафіксованим `targetRevision` і inline-значеннями. Анотація `sync-wave` задає порядок.

### `charts/webapp/Chart.yaml`
Метадані чарта. `version` (чарта) і `appVersion` (застосунку) розділені.

### `charts/webapp/values.yaml`
Кастомізується: `image.{repository,tag,pullPolicy}`, `replicaCount`, `resources`, `autoscaling.{enabled,minReplicas,maxReplicas,targetCPUUtilizationPercentage}`, `ingress.{enabled,className,host,tls,annotations}`, `podDisruptionBudget.{enabled,minAvailable}`, `networkPolicy.enabled`, `env`, `securityContext`, `nodeSelector`, `tolerations`, `affinity`. Кожен ключ із коментарем.

### `charts/webapp/values.schema.json`
Обовʼязкові: `image.repository`, `image.tag`. Заборонений `latest`. `replicaCount` — integer ≥ 1. `resources.requests` обовʼязкові.

### `charts/webapp/templates/deployment.yaml`
Умовний `replicas`, повний `securityContext`, `emptyDir` на `/tmp`, дві probes, `checksum/config`, `maxUnavailable: 0`, `topologySpreadConstraints`, downward API для `POD_NAME`.

### `charts/webapp/templates/networkpolicy.yaml`
Рендериться під `networkPolicy.enabled`. Дозволяє ingress тільки з `ingress-nginx`, egress тільки на DNS і 443.

### `tenants/*/appproject.yaml`
Межі того, що тенант може розгортати: тільки свій namespace, тільки цей репозиторій, жодних кластерних ресурсів.

### `tenants/*/networkpolicy.yaml`
default-deny + DNS + ingress-nginx. Найважливіший файл для демонстрації ізоляції.

### `envs/{dev,prod}/*.yaml`
Тільки значення. `dev`: 1 репліка, HPA вимкнено, менші ліміти. `prod`: 3 репліки, HPA увімкнено, PDB `minAvailable: 2`.

### `.github/workflows/ci-manifests.yml`
**Тригери:** `pull_request` на `charts/**`, `platform/**`, `tenants/**`, `envs/**`.
**Джоби:** `lint` (yamllint, helm lint, helm unittest) → `validate` (matrix по env×tenant: `helm template | kubeconform -strict`).
**Очікуваний потік:** обидва джоби зелені → мерж дозволено.

### `.github/workflows/ci-app.yml`
**Тригери:** `push` у `main` і `pull_request` на `src/webapp/**`.
**Джоби:** `test` (ruff + pytest) → `build` (docker build, trivy scan із `--exit-code 1`, push у GHCR тільки на `main`).

### `.github/workflows/promote.yml`
**Тригери:** `workflow_run` після успішного `ci-app` на `main`.
**Дія:** оновлює `image.tag` у `envs/dev/*.yaml`, відкриває PR із лейблом `promotion`.

### `Makefile`
Цілі: `up`, `down`, `bootstrap`, `verify`, `lint`, `test`, `drift-demo`, `seal-secret`, `help`.

---

## 9. CI/CD пайплайн

```
┌────────────────── CI (GitHub Actions) ──────────────────┐
│                                                          │
│  PR відкрито                                             │
│   ├─ yamllint         (усі YAML)                         │
│   ├─ helm lint        (charts/webapp)                    │
│   ├─ helm unittest    (5 тестів)                         │
│   ├─ helm template + kubeconform -strict                 │
│   │     matrix: {dev,prod} × {alpha,beta} = 4 запуски    │
│   ├─ ruff check       (якщо зачеплено src/)              │
│   ├─ pytest           (якщо зачеплено src/)              │
│   ├─ gitleaks detect  (повна історія)                    │
│   └─ trivy fs src/                                       │
│                                                          │
│  Усі — required status checks. Мерж заблокований.        │
│                                                          │
│  Мерж у main (тільки якщо змінено src/)                  │
│   ├─ docker build                                        │
│   ├─ trivy image --exit-code 1 --severity CRITICAL       │
│   ├─ docker push ghcr.io/.../webapp:${GITHUB_SHA}        │
│   └─ promote.yml → PR: bump image.tag у envs/dev/        │
│                                                          │
└──────────────────────────────────────────────────────────┘
                          │
              PR змержено (ревʼю людиною)
                          │
┌────────────────── CD (Argo CD) ─────────────────────────┐
│                                                          │
│  polling кожні 3 хв (або webhook)                        │
│   ├─ порівняння desired (Git) vs live (кластер)          │
│   ├─ якщо OutOfSync → застосувати diff                   │
│   ├─ sync waves визначають порядок                       │
│   ├─ health assessment (Deployment progressing/healthy)   │
│   └─ selfHeal: відкат будь-якої позагітової зміни        │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

**Стратегія тегування образів.** Основний тег — повний `github.sha` (40 символів). Він унікальний, незмінний і однозначно вказує на коміт. Додатково `sha-<7 символів>` для читабельності. **Ніколи** `latest`: він робить неможливим визначити, що саме запущено, і ламає ідемпотентність GitOps (Git не змінюється, а образ змінюється).

**Промоушен між середовищами.** Той самий digest образу переїжджає з `envs/dev/` у `envs/prod/` через PR. Перезбірки немає. Це принципово: артефакт, протестований у dev, і артефакт у prod — байт-у-байт той самий.

**Стратегія відкату.** Три рівні:
1. `git revert` коміту з bump-ом → Argo CD синхронізує попередню версію. Це основний механізм. Час — до 3 хвилин.
2. Argo CD UI → History and Rollback → попередня ревізія. Швидше, але створює дрейф із Git, тому одразу після цього треба зробити revert у Git.
3. `kubectl rollout undo` — аварійний варіант. З `selfHeal: true` Argo CD відкотить твій відкат назад через хвилину. Обовʼязково згадай цю пастку в документації, це показує розуміння механіки.

**Чого в пайплайні немає і чому.** Немає кроку `kubectl apply`. Взагалі. У GitHub Actions немає kubeconfig, немає секрета з кластером, немає ServiceAccount. Це головна архітектурна властивість, і в README вона має бути сформульована явно.

---

## 10. Infrastructure as Code

Terraform у цьому проєкті **не використовується** свідомо — кластер локальний, хмарних ресурсів немає. IaC тут реалізується через декларативні Kubernetes-маніфести та Helm-значення, а Argo CD виконує роль движка застосування (аналог `terraform apply` у нескінченному циклі).

Що варто пояснити в `docs/decisions/`:

- **Стан.** У Terraform стан зберігається окремо і може розійтися з реальністю. У Kubernetes стан живе в etcd і є авторитетним, а Argo CD порівнює Git із ним безперервно. Це фундаментально надійніша модель для того, що вже є в кластері.
- **Дрейф.** Terraform виявляє дрейф тільки коли ти запускаєш `plan`. Argo CD виявляє його постійно і може виправляти автоматично.
- **Ідемпотентність.** Обидва декларативні. Різниця в тому, хто ініціює звірку.
- **Де Terraform усе ж потрібен.** Створення самого кластера, VPC, IAM, керованих БД. Це Проєкт B, і в README варто поставити перехресне посилання.

Якщо захочеш додати хмарний варіант (розширення): невеликий Terraform-модуль, що піднімає VM у Hetzner чи DigitalOcean і встановлює k3s через `cloud-init`, зі станом у S3-сумісному сховищі. Тримай його в окремому каталозі `terraform/` і чітко познач як опційний.

---

## 11. Дизайн Kubernetes

**Namespaces.** `argocd`, `ingress-nginx`, `cert-manager`, `kube-system`, `monitoring`, `team-alpha`, `team-beta`. Розділення платформи і тенантів — це межа відповідальності: платформна команда володіє першими, продуктові команди — останніми.

**Deployment.** `maxUnavailable: 0` + `maxSurge: 1`. `topologySpreadConstraints` по вузлах, щоб репліки не опинилися на одному воркері. `terminationGracePeriodSeconds: 30` і `preStop` sleep 5s — та сама логіка, що в твоїй дипломній, і тут її треба задокументувати в чарті коментарем.

**Service.** ClusterIP. LoadBalancer заборонений квотою: у хмарі кожен LB коштує грошей, і платформна модель передбачає єдину точку входу.

**Ingress.** Один на тенанта, маршрутизація за hostname, TLS через cert-manager. `ingressClassName: nginx` явно, бо дефолтний клас — джерело плутанини.

**ConfigMap / Secret.** ConfigMap із чексумою в анотації поду. Secret надходить із SealedSecret, монтується як env, не як файл (простіше і достатньо для цього застосунку).

**PersistentVolumes.** Не використовуються. Застосунок stateless навмисно — стан і бекапи це Проєкт D. Це варто написати явно, бо відсутність PV інакше виглядає як прогалина.

**Resource requests/limits.** Requests визначають планування і базу для HPA. Limits захищають сусідів. Memory limit == memory request (гарантований QoS клас `Guaranteed` за памʼяттю уникає OOM через overcommit). CPU limit вищий за request, бо CPU — стискуваний ресурс і throttling гірший за burst.

**Probes.** Liveness `/health`: тільки чи живий процес; має бути дешевою і не залежати від зовнішніх сервісів, інакше падіння БД спричинить каскадні рестарти. Readiness `/ready`: чи готовий приймати трафік; може перевіряти залежності. Періоди різні: readiness агресивніша (5s), liveness консервативніша (10s, initialDelay 20s).

**Autoscaling.** HPA на CPU, `minReplicas: 2`, `maxReplicas: 6` у prod. Вимкнено в dev. Ти вже знаєш KEDA з дипломної — тут навмисно простий HPA, бо фокус на платформі; у README постав посилання на попередній проєкт із поясненням, чому там був KEDA.

**PodDisruptionBudget.** `minAvailable: 2` у prod. Захищає під час drain вузла. Продемонструй: `kubectl drain <node>` і покажи, що eviction блокується, поки не піднімуться нові поди.

**RBAC.** Три рівні: (1) ServiceAccount застосунку — без жодних прав, `automountServiceAccountToken: false`; (2) Role для «команди тенанта» — read-only у своєму namespace плюс `create` на pods/exec для дебагу; (3) Argo CD AppProject — обмежує, що може створювати сам GitOps-контролер.

**NetworkPolicies.** Default-deny в обох напрямках, потім мінімальні дозволи. Це єдиний спосіб довести, що ти розумієш, що за замовчуванням у Kubernetes **усі поди можуть говорити з усіма**.

**Helm.** Один чарт, багато релізів. Це і є суть платформи: одна перевірена абстракція, багато споживачів.

---

## 12. Моніторинг і обсервабельність

Тут навмисно мінімум — повний стек це Проєкт C. Мета: платформа має бути спостережуваною достатньо, щоб довести її здоровʼя.

**Метрики.** `kube-prometheus-stack` із урізаними values (без Alertmanager, з коротким retention 6h, без persistent storage). Застосунок віддає `/metrics`, ServiceMonitor створюється чартом під прапорцем.

**Дашборди.** Два, збережені як JSON у `platform/monitoring/dashboards/`:
1. **Platform health** — стан Argo CD Applications (synced/healthy), кількість подів по namespace, споживання проти квоти тенанта.
2. **Tenant webapp** — RPS, частка помилок, p50/p95/p99 латентності, кількість реплік проти цілі HPA.

**Логи.** Не в цьому проєкті. `kubectl logs` достатньо. Явно познач як обмеження і постав посилання на Проєкт C.

**Приклади алертів** (описати в `docs/`, реалізувати в Проєкті C):

| Алерт | Вираз (спрощено) | Чому саме так |
|---|---|---|
| `ArgoAppOutOfSync` | `argocd_app_info{sync_status!="Synced"} > 0` for 15m | Дрейф, який self-heal не зміг виправити = реальна проблема |
| `ArgoAppUnhealthy` | `argocd_app_info{health_status="Degraded"}` for 5m | Симптом, а не причина |
| `PodCrashLooping` | `increase(kube_pod_container_status_restarts_total[15m]) > 3` | Вікно, а не миттєве значення |
| `HighErrorRate` | частка 5xx > 1% for 5m | Симптом з точки зору користувача |
| `HighLatencyP99` | p99 > 500ms for 10m | Латентність, а не CPU |
| `CertificateExpiringSoon` | `certmanager_certificate_expiration_timestamp_seconds - time() < 14*86400` | 14 днів — час зреагувати |
| `TenantQuotaNearlyExhausted` | `kube_resourcequota{type="used"} / kube_resourcequota{type="hard"} > 0.9` | Попередження до того, як деплої почнуть падати |
| `PDBViolated` | `kube_poddisruptionbudget_status_current_healthy < kube_poddisruptionbudget_status_desired_healthy` | Реальна втрата надійності |
| `NodeDiskPressure` | `predict_linear(node_filesystem_avail_bytes[6h], 4*3600) < 0` | Прогноз, а не статичний поріг |

Аргумент, який варто написати в README: алерти на **симптоми** (користувачі бачать помилки), а не на **причини** (CPU високий). Високий CPU без деградації сервісу — це не інцидент.

---

## 13. Безпека

Кожен пункт із конкретною реалізацією, не теорією.

**Керування секретами.**
Реалізація: контролер `sealed-secrets` у `kube-system`, секрети комітяться як `SealedSecret`. Скрипт `scripts/seal-secret.sh` — єдиний санкціонований шлях.
ADR-002 має порівняти три варіанти:

| Підхід | Плюси | Мінуси | Вердикт |
|---|---|---|---|
| SOPS + age + ksops | Гнучкий, працює і поза Kubernetes | Потребує кастомного плагіна в Argo CD repo-server, ускладнює апгрейди | Відхилено для MVP |
| External Secrets Operator | Секрети живуть у хмарному сховищі, ротація централізована | Потребує зовнішнього провайдера (платного або хмарного) | Відхилено локально, зазначено як розширення |
| Sealed Secrets | Нуль зовнішніх залежностей, працює з ванільним Argo CD | Приватний ключ привʼязаний до кластера, потребує бекапу | **Обрано** |

**Least privilege IAM/RBAC.**
Реалізація: ServiceAccount застосунку без прав і з `automountServiceAccountToken: false`; AppProject обмежує Argo CD; Role тенанта покриває тільки свій namespace.
Перевірка: `kubectl auth can-i --list --as=system:serviceaccount:team-alpha:webapp -n team-alpha` — скріншот у README.

**Сканування контейнерів.**
Trivy у `ci-app.yml` з `--exit-code 1 --severity CRITICAL`. Плюс щотижневий скан за розкладом, бо нові CVE зʼявляються після збірки.

**Сканування залежностей.**
Dependabot через `.github/dependabot.yml`: `pip` для `src/webapp`, `github-actions` для воркфлоу, `docker` для базового образу.

**Сканування маніфестів.**
`kubeconform -strict` (валідність схеми) плюс перевірка політик: наприклад, `trivy config` по відрендереному шаблону, який ловить відсутній `runAsNonRoot`, привілейовані контейнери, відсутні ліміти.

**Kubernetes security.**
Pod Security Admission у режимі `restricted` на тенантських namespace. NetworkPolicy default-deny. ResourceQuota із `count/services.loadbalancers: "0"`.

**Non-root контейнери.**
`USER 10001` у Dockerfile, `runAsNonRoot: true` + `runAsUser: 10001` + `readOnlyRootFilesystem: true` + `capabilities.drop: [ALL]` у чарті. Перевірка: `kubectl exec ... -- id`.

**Пінінг образів.**
Базовий образ за digest у Dockerfile. Helm-чарти платформи із зафіксованим `targetRevision`. Argo CD із зафіксованої версії маніфесту.

**Захист гілок.**
Require PR, require status checks, require linear history, заборона force-push у `main`. CODEOWNERS на `charts/` і `platform/`.

**Безпека CI/CD.**
Найважливіше: CI **не має** доступу до кластера. Далі: `permissions:` явно вказані в кожному воркфлоу за принципом мінімуму (`contents: read` за замовчуванням, `packages: write` тільки в build-джобі). Усі сторонні actions запінені за commit SHA, а не за тегом (тег можна перемістити, SHA — ні). Це те, що ловлять на аудитах, і майже ніхто з джуніорів не робить.

**gitleaks.**
Запуск по повній історії на кожному PR. Прямо адресує проблему, яка вже була в твоєму `iac-deploy-pipeline`. У README це можна згадати одним реченням як мотивацію — це чесно і читається сильно.

---

## 14. Надійність і production-практики

**Health checks.** Три рівні: probes Kubernetes (под), health assessment Argo CD (Application), `scripts/verify.sh` (платформа цілком).

**Надлишковість.** 3 репліки в prod, розкидані по вузлах через `topologySpreadConstraints`. Argo CD у kind — одна репліка; чесно познач це як обмеження і опиши HA-конфігурацію в `docs/`.

**Rolling deployments.** `maxUnavailable: 0`, `maxSurge: 1`, readiness gate.

**Rollback.** Три механізми, описані в секції 9, плюс явне попередження про конфлікт `kubectl rollout undo` із `selfHeal`.

**Бекапи.** Що саме треба бекапити в цій системі: (1) приватний ключ sealed-secrets — без нього всі секрети втрачені назавжди; (2) сам Git-репозиторій — це вся конфігурація. Стан застосунку бекапити нема чого, він stateless. Опиши це в `docs/security.md`.

**Disaster recovery.** Процедура: створити новий кластер (`make up`), відновити ключ sealed-secrets із бекапу, застосувати bootstrap, застосувати root-app, дочекатися синхронізації. Заміряй фактичний час і впиши в README як **виміряний RTO**. Це рідкісний і сильний артефакт.

**Autoscaling.** HPA у prod. `behavior.scaleDown.stabilizationWindowSeconds: 300`, щоб не було флапінгу — ти це вже знаєш із дипломної.

**Immutable infrastructure.** Образи за digest, жодного `latest`, жодного `kubectl edit` як санкціонованої дії. Кластер відтворюваний з нуля.

**Ідемпотентність.** Багаторазовий запуск `bootstrap.sh` має давати той самий результат. Перевір явно: запусти двічі поспіль.

**Що відбувається при відмові кожного компонента** — таблиця для README:

| Відмовляє | Наслідок | Чи страждає трафік |
|---|---|---|
| Argo CD | Нові зміни не застосовуються, дрейф не виправляється | Ні |
| ingress-nginx | Зовнішній трафік не проходить | Так, повністю |
| cert-manager | Сертифікати не оновлюються; чинні працюють до закінчення | Ні, відкладено |
| sealed-secrets | Нові SealedSecret не розшифровуються; наявні Secret живі | Ні |
| metrics-server | HPA не масштабує, тримає останню кількість реплік | Ні, доки навантаження стабільне |
| один воркер | Поди перепризначаються, PDB захищає доступність | Коротка деградація |
| GitHub недоступний | Argo CD не бачить нових комітів, кластер працює далі | Ні |

Ця таблиця — сама по собі привід для десяти питань на співбесіді, і ти на них відповіси, бо сама її склала.

---

## 15. Стратегія тестування

| Що тестуємо | Інструмент | Команда | Де запускається |
|---|---|---|---|
| Код застосунку | pytest | `pytest -q src/webapp/tests` | CI, PR |
| Стиль коду | ruff | `ruff check src/` | CI, PR |
| Docker-образ | Trivy | `trivy image --exit-code 1 --severity CRITICAL $IMG` | CI, після build |
| Non-root у образі | docker | `docker run --rm --entrypoint id $IMG` | CI, assert на uid 10001 |
| Синтаксис YAML | yamllint | `yamllint -c .yamllint.yaml .` | CI, PR |
| Helm-чарт, синтаксис | helm | `helm lint charts/webapp` | CI, PR |
| Helm-чарт, логіка | helm-unittest | `helm unittest charts/webapp` | CI, PR |
| Валідність маніфестів | kubeconform | `helm template ... \| kubeconform -strict -summary -` | CI, matrix |
| Політики безпеки | Trivy config | `trivy config <rendered-dir>` | CI, PR |
| Секрети в репозиторії | gitleaks | `gitleaks detect --source . --redact` | CI + cron |
| Схема values | helm | `helm template -f envs/prod/team-alpha.yaml` (падає при `latest`) | CI |
| Ізоляція мережі | kubectl | curl із `team-alpha` у `team-beta` → має бути таймаут | `verify.sh` |
| RBAC | kubectl | `kubectl auth can-i --list --as=system:serviceaccount:...` | `verify.sh` |
| Доступність застосунку | curl | `curl -kfsS https://alpha.platform.local/health` | `verify.sh` |
| Реконсиляція | скрипт | `scripts/drift-demo.sh` | вручну, для демо |
| Bootstrap з нуля | make | `make down && make up && ./scripts/bootstrap.sh && ./scripts/verify.sh` | вручну, перед релізом |

`scripts/verify.sh` варто написати як набір асертів, що виходить із ненульовим кодом при провалі. Це перетворює «здається, працює» на перевірюваний факт, і його можна показати на співбесіді.

---

## 16. Сценарії траблшутингу

### Сценарій 1 — Application застряг у `OutOfSync` із `ComparisonError`

**Симптоми.** В UI Argo CD застосунок червоний, статус `Unknown` або `OutOfSync`, у деталях помилка на кшталт `rpc error: code = Unknown desc = Manifest generation error`.

**Діагностика.**
```bash
kubectl -n argocd get application <name> -o jsonpath='{.status.conditions}' | jq
kubectl -n argocd logs deploy/argocd-repo-server --tail=100
helm template test charts/webapp -f envs/prod/team-alpha.yaml   # відтворити локально
```

**Можливі причини.** Синтаксична помилка в шаблоні; `values.schema.json` відхиляє значення; шлях `valueFiles` невірний; чарт посилається на залежність, яку не завантажено; `targetRevision` вказує на неіснуючу гілку чи тег.

**Рішення.** Відтворити `helm template` локально — помилка буде та сама і читабельніша. Якщо локально працює, а в Argo ні, майже завжди причина у відносних шляхах `valueFiles`: вони обчислюються від кореня репозиторію, а не від каталогу чарта.

---

### Сценарій 2 — Поди стартують, але жоден DNS-запит не працює

**Симптоми.** Под у `Running`, readiness проходить, але будь-яке звернення до іншого сервісу за іменем висить і завершується таймаутом. У логах застосунку `Temporary failure in name resolution`.

**Діагностика.**
```bash
kubectl -n team-alpha run dnstest --rm -it --image=busybox:1.36 --restart=Never -- \
  nslookup kubernetes.default
kubectl -n team-alpha get networkpolicy
kubectl -n team-alpha describe networkpolicy default-deny-all
kubectl -n kube-system get pods -l k8s-app=kube-dns
```

**Причина.** Політика `default-deny-all` із `policyTypes: [Ingress, Egress]` блокує весь вихідний трафік, включно з DNS на порт 53 до `kube-system`. Це найпоширеніша помилка при першому впровадженні NetworkPolicy.

**Рішення.** Додати політику, що дозволяє egress на порт 53 UDP і TCP до namespace `kube-system` із селектором `k8s-app: kube-dns`. Не забути **обидва** протоколи: TCP потрібен для відповідей більших за 512 байт.

---

### Сценарій 3 — Ingress повертає 502 Bad Gateway

**Симптоми.** `curl https://alpha.platform.local` повертає сторінку 502 від nginx. Поди при цьому `Running`.

**Діагностика.**
```bash
kubectl -n team-alpha get endpoints webapp
kubectl -n team-alpha get svc webapp -o yaml | grep -A3 ports
kubectl -n team-alpha describe pod -l app.kubernetes.io/name=webapp | grep -A5 Readiness
kubectl -n ingress-nginx logs deploy/ingress-nginx-controller --tail=50
kubectl -n team-alpha port-forward svc/webapp 8000:80   # обійти ingress
```

**Можливі причини.** (1) `endpoints` порожні, бо readiness probe не проходить; (2) `targetPort` у Service не збігається з `containerPort`; (3) селектор Service не збігається з лейблами поду; (4) NetworkPolicy блокує трафік із `ingress-nginx`.

**Рішення.** Порожній список endpoints одразу вказує на (1) або (3). Якщо endpoints є, а 502 залишається — це (2) або (4). `port-forward` напряму на Service розділяє ці випадки: якщо працює, проблема між ingress і Service, тобто NetworkPolicy.

---

### Сценарій 4 — Certificate назавжди в стані `Ready=False`

**Симптоми.** `kubectl get certificate` показує `READY: False` годинами. Ingress віддає самопідписаний дефолтний сертифікат nginx.

**Діагностика.** Проходь ланцюжок по порядку:
```bash
kubectl -n team-alpha describe certificate webapp-tls
kubectl -n team-alpha get certificaterequest
kubectl -n team-alpha describe certificaterequest <name>
kubectl -n team-alpha get order
kubectl -n team-alpha describe order <name>
kubectl -n team-alpha get challenge
kubectl -n team-alpha describe challenge <name>
kubectl -n cert-manager logs deploy/cert-manager --tail=100
```

**Можливі причини.** ClusterIssuer не існує або в стані `Ready=False`; для HTTP-01 challenge не досягається ззовні; для DNS-01 невірний API-токен; досягнуто rate limit Let's Encrypt (50 сертифікатів на домен на тиждень); імʼя ClusterIssuer в анотації написано з помилкою.

**Рішення.** Ланцюжок Certificate → CertificateRequest → Order → Challenge завжди веде до реальної причини на останньому рівні. При роботі з Let's Encrypt завжди починай зі staging-сервера: його ліміти набагато м'якші, а перемикання на production — це один рядок.

---

### Сценарій 5 — Argo CD і HPA борються за кількість реплік

**Симптоми.** Кількість реплік осцилює. В Argo CD застосунок постійно `OutOfSync` по полю `spec.replicas`, синхронізується, знову розходиться.

**Діагностика.**
```bash
kubectl -n team-alpha get hpa
kubectl -n argocd get application team-alpha-prod -o jsonpath='{.status.resources}' | jq
kubectl -n team-alpha get deploy webapp -o jsonpath='{.spec.replicas}'
helm template ... | grep -A2 "replicas:"
```

**Причина.** Чарт рендерить `spec.replicas`, HPA його змінює, Argo CD із `selfHeal: true` повертає назад, HPA знову змінює.

**Рішення (правильне).** Не рендерити `replicas` взагалі, коли HPA увімкнено:
```yaml
{{- if not .Values.autoscaling.enabled }}
replicas: {{ .Values.replicaCount }}
{{- end }}
```
**Рішення (обхідне, для інших полів).** Анотація `argocd.argoproj.io/compare-options: IgnoreExtraneous` або секція `ignoreDifferences` у Application. Але для реплік правильний шлях — не генерувати поле.

Це один із найкращих сценаріїв для співбесіди: він показує розуміння того, що кілька контролерів можуть володіти одним полем.

---

### Сценарій 6 — SealedSecret не розшифровується

**Симптоми.** SealedSecret створено, а Secret не зʼявляється. `kubectl describe sealedsecret` показує помилку розшифрування.

**Діагностика.**
```bash
kubectl -n team-alpha describe sealedsecret app-secrets
kubectl -n kube-system logs deploy/sealed-secrets-controller --tail=50
kubectl -n kube-system get secrets -l sealedsecrets.bitnami.com/sealed-secrets-key
```

**Причина.** Секрет зашифровано публічним ключем іншого кластера (типово після `make down && make up` — контролер генерує нову пару ключів); або SealedSecret скопійовано в інший namespace, ніж той, для якого його шифрували.

**Рішення.** Перешифрувати всі секрети після перестворення кластера, або відновити приватний ключ із бекапу перед bootstrap. Це і є той момент, який робить бекап ключа критичним — задокументуй його.

---

### Сценарій 7 — Под у `CreateContainerConfigError` після ввімкнення Pod Security Admission

**Симптоми.** Под не стартує, у `describe` помилка про порушення політики `restricted`.

**Діагностика.**
```bash
kubectl -n team-alpha describe pod <name> | tail -20
kubectl get ns team-alpha -o jsonpath='{.metadata.labels}' | jq
kubectl -n team-alpha get pod <name> -o jsonpath='{.spec.securityContext}' | jq
```

**Причина.** Профіль `restricted` вимагає `runAsNonRoot: true`, `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`, `seccompProfile.type: RuntimeDefault`. Відсутність будь-якого з них блокує створення.

**Рішення.** Додати повний набір у чарт. Ефективний спосіб знайти всі порушення заздалегідь: тимчасово поставити лейбл `warn` замість `enforce` і подивитися попередження при `kubectl apply --dry-run=server`.

---

### Сценарій 8 — Диск вузла kind заповнений

**Симптоми.** Поди в `Evicted`, вузол має taint `node.kubernetes.io/disk-pressure`, нові поди в `Pending`.

**Діагностика.**
```bash
kubectl describe node <node> | grep -A5 Conditions
docker exec -it gitops-platform-worker df -h /
docker system df
crictl images   # усередині вузла
```

**Причина.** kind-вузол — це Docker-контейнер, і його ФС ділить місце з хостом. Накопичені образи від багатьох ітерацій збірки заповнюють простір.

**Рішення.** `docker system prune -af` на хості; всередині вузлів образи прибирає kubelet garbage collection, але його пороги в kind консервативні. Профілактично: не завантажуй кожну збірку в кластер через `kind load`, використовуй GHCR.

---

## 17. Структура README

```markdown
# gitops-k8s-platform

[badges: CI, manifests validation, security scan, license, k8s version]

Однорядковий опис: multi-tenant Kubernetes platform managed entirely through GitOps
with Argo CD, running locally on kind.

[GIF: демонстрація self-heal — 10 секунд]

## What this is
2–3 абзаци: проблема дрейфу, чому pull-based CD, що саме розгорнуто.

## Architecture
[діаграма]
Опис потоків: розробник → Git → CI → registry; Git → Argo CD → кластер.
Явна теза: CI has no cluster credentials.

## Technology stack
[таблиця з секції 5, скорочена до 3 колонок]

## Features
- App-of-apps bootstrap: одна команда від порожнього ноутбука до платформи
- Two isolated tenants: RBAC, NetworkPolicy, ResourceQuota, Pod Security Admission
- Custom Helm chart with values.schema.json validation
- Sealed Secrets: encrypted secrets committed to Git
- Automatic drift correction (демонстрація нижче)
- PR-based promotion dev → prod, той самий digest образу
- TLS via cert-manager
- CI: yamllint, helm lint, helm unittest, kubeconform, Trivy, gitleaks

## Prerequisites
docker, kind, kubectl, helm, kubeseal — з версіями.

## Quick start
```bash
make up && make bootstrap && make verify
```
Що очікувати, скільки часу, як зайти в UI.

## Repository layout
[дерево з коментарями, скорочене]

## How deployment works
Промоушен покроково, із прикладом diff-у одного рядка.

## CI/CD
[діаграма пайплайну]
Чому CI не має доступу до кластера.

## Security
Список контролів із посиланням на docs/security.md.

## Reliability
Таблиця «що відбувається при відмові компонента».
Виміряний час відновлення з нуля: X хвилин.

## Demonstrations
### Drift correction
[GIF або скріншоти + вивід скрипта]
### Tenant isolation
[скріншот таймауту curl між namespace]
### Rollback
[скріншот: git revert → час до відновлення]
### Blocked merge
[скріншот PR із заблокованим мержем через failing check]

## Troubleshooting
Посилання на docs/troubleshooting.md + 2 найчастіші проблеми одразу тут.

## Architecture decisions
Посилання на чотири ADR із одним реченням про кожне.

## Known limitations
Чесний список: single-replica Argo CD, локальний кластер, self-signed TLS
локально, логів немає (див. Проєкт C), stateful workloads немає (див. Проєкт D).

## What I learned
3–5 речень своїми словами. Найчитабельніша секція для інтервʼюера.

## Future improvements
Argo Rollouts canary, Kyverno policies, External Secrets Operator, multi-cluster.

## License
```

**Які скріншоти зробити (мінімум сім):**
1. Дерево Applications в Argo CD UI, усе зелене.
2. Вивід `drift-demo.sh` із моментом відкату.
3. Таймаут curl між тенантами.
4. `kubectl auth can-i --list` для ServiceAccount застосунку (порожній список).
5. PR із заблокованим мержем через провалену перевірку.
6. Браузер із валідним HTTPS на `alpha.platform.local`.
7. Grafana-дашборд з health платформи.

Плюс два GIF: self-heal і повний bootstrap у прискоренні.

---

## 18. Стратегія комітів

24 коміти, які виглядають як природний розвиток проєкту. Conventional Commits.

```
chore: initialize repository structure
chore: add Makefile with cluster lifecycle targets
feat(app): add FastAPI service with health and readiness endpoints
test(app): add unit tests for health endpoints
feat(app): containerize with multi-stage non-root Dockerfile
fix(app): use venv instead of pip --user so non-root user can import deps
feat(kind): add three-node cluster config with ingress port mappings
feat(argocd): bootstrap Argo CD via kustomize at pinned version
feat(gitops): add root application implementing app-of-apps pattern
feat(platform): deploy ingress-nginx via Argo CD
feat(platform): deploy cert-manager with self-signed cluster issuer
fix(platform): add sync waves so CRDs are installed before issuers
feat(platform): deploy metrics-server and sealed-secrets controller
feat(chart): add webapp Helm chart with deployment, service and ingress
feat(chart): add values.schema.json rejecting the latest tag
feat(chart): add HPA, PDB and NetworkPolicy templates
fix(chart): omit replicas when autoscaling is enabled to stop HPA conflict
test(chart): add helm-unittest coverage for security context and autoscaling
feat(tenants): add team-alpha namespace with quota, RBAC and network policies
feat(tenants): add team-beta and verify cross-namespace traffic is denied
feat(tenants): restrict Argo CD via per-tenant AppProject
feat(secrets): manage tenant credentials with Sealed Secrets
ci: validate manifests with yamllint, helm lint and kubeconform
ci: build, scan with Trivy and publish image to GHCR
ci: open automated promotion PR on successful image build
ci: add gitleaks and scheduled dependency scanning
docs: add architecture decision records
docs: add troubleshooting runbook with eight failure scenarios
docs: write README with demonstrations and measured recovery time
chore: tag v1.0.0
```

Три коміти навмисно є `fix:` реальних проблем, з якими ти справді зіткнешся (venv, sync waves, HPA-конфлікт). Історія, у якій ніколи нічого не ламалося, виглядає штучно.

Роби це через pull request-и, хоча б частину. Три-чотири PR із нормальним описом і зеленими перевірками — це видно в Insights і виглядає як робота в команді.

---

## 19. Оформлення репозиторію

**Опис:**
> Multi-tenant Kubernetes platform managed entirely through GitOps. Argo CD app-of-apps, custom Helm chart, tenant isolation with RBAC and NetworkPolicies, Sealed Secrets, cert-manager, and a validation-first CI pipeline. Runs locally on kind at zero cost.

**Топіки:** `kubernetes` `gitops` `argocd` `helm` `platform-engineering` `devops` `cert-manager` `sealed-secrets` `kind` `github-actions` `devsecops` `multi-tenancy` `infrastructure-as-code`

**Бейджі:** статус `ci-manifests`, статус `ci-app`, статус `security`, ліцензія, версія Kubernetes, версія Argo CD.

**Релізи:** `v0.1.0` після платформного шару, `v0.2.0` після тенантів, `v1.0.0` після документації. Кілька релізів показують ітеративність.

**Issues:** створи 6–8 реальних issue до того, як реалізовувати відповідні фічі, і закривай їх через PR із `Closes #N`. Це коштує 15 хвилин і робить репозиторій схожим на робочий, а не на дамп.

**Projects board:** необовʼязково. Дошка з трьома колонками і закритими картками — приємно, але низька віддача. Роби, якщо є час.

**CHANGELOG.md:** формат Keep a Changelog, три записи відповідно до релізів.

**LICENSE:** MIT.

**Branch protection:** require PR, require status checks, require linear history.

**CODEOWNERS:** `/charts/ @sofa4578`, `/platform/ @sofa4578`. Формальність для одного власника, але це стандартний артефакт і його наявність помічають.

---

## 20. Подання в резюме

**Назва для CV:**
> **GitOps Kubernetes Platform** — multi-tenant platform with Argo CD, Helm and policy-driven CI

**Булети (нічого не перебільшено, жодних тверджень про реальних користувачів):**

- Designed and built a multi-tenant Kubernetes platform managed entirely through GitOps, using Argo CD in app-of-apps mode to reconcile 8 platform components and 4 tenant applications from a single Git repository.

- Authored a reusable Helm chart with `values.schema.json` validation, HPA, PodDisruptionBudget, NetworkPolicy templates and a restricted-profile security context; covered it with 5 unit tests via helm-unittest.

- Implemented tenant isolation on three layers — namespace-scoped RBAC, default-deny NetworkPolicies and ResourceQuotas — and verified cross-tenant traffic is blocked as part of an automated verification script.

- Built a validation-first CI pipeline (yamllint, helm lint, helm unittest, kubeconform, Trivy, gitleaks) enforced as required status checks, deliberately keeping cluster credentials out of CI by using pull-based delivery.

- Managed secrets as encrypted `SealedSecret` resources committed to Git, and documented the private-key backup procedure as the platform's single critical recovery dependency.

- Measured full platform recovery from an empty machine at under X minutes and documented the disaster-recovery procedure. *(підстав реальне число)*

---

## 21. Питання на співбесіді

**1. Чому Argo CD, а не `kubectl apply` у GitHub Actions?**
Push-модель вимагає зберігати креденшели кластера в CI, тож компрометація CI дає доступ до кластера. Pull-модель означає, що креденшели ніколи не залишають кластер. Крім того, push нічого не знає про дрейф: якщо хтось змінить ресурс руками, пайплайн цього не побачить до наступного запуску.

**2. Що таке app-of-apps і навіщо він?**
Один Argo Application, який керує каталогом, що містить інші Application. Дає одну точку входу для bootstrap і робить залежності явними. Альтернатива — застосовувати десяток Application руками, що суперечить самій ідеї.

**3. Що робить `selfHeal: true` і коли його не варто вмикати?**
Автоматично відкочує будь-яку зміну, зроблену поза Git. Не варто вмикати там, де інший контролер легітимно володіє тим самим полем — класичний випадок HPA і `spec.replicas`. Тому в моєму чарті поле `replicas` не рендериться, коли HPA увімкнено.

**4. Навіщо sync waves?**
Порядок застосування. cert-manager має встановити свої CRD раніше, ніж зʼявиться ClusterIssuer, інакше синхронізація впаде з помилкою невідомого типу. Waves задають детермінований порядок.

**5. Як захищені секрети?**
Sealed Secrets: асиметричне шифрування, публічним ключем шифрую локально, приватний ключ живе тільки в контролері всередині кластера. Зашифрований секрет привʼязаний до пари namespace+name, тому перенести його в інший namespace для читання неможливо.

**6. Чому не Vault?**
Правильне розгортання Vault із HA, unsealing і аудитом — це окремий проєкт супроводу, і погано налаштований Vault створює хибне відчуття безпеки. Для одноосібної платформи Sealed Secrets дає потрібну властивість — секрети безпечно лежать у Git — без зовнішніх залежностей. Наступний крок для реальної системи — External Secrets Operator із хмарним сховищем, бо він додає централізовану ротацію.

**7. Що станеться, якщо кластер знищити?**
Уся конфігурація в Git і відновлюється, але приватний ключ sealed-secrets генерується заново, тому наявні SealedSecret стануть нерозшифровуваними. Тому бекап цього ключа — єдина критична залежність відновлення, і вона задокументована окремо.

**8. Що відбувається, коли падає Argo CD?**
Робочі навантаження продовжують працювати. Втрачається реконсиляція: нові зміни не застосовуються, дрейф не виправляється. Це деградація керованості, а не доступності.

**9. Як влаштована ізоляція тенантів?**
Три рівні. RBAC обмежує, хто що може робити. NetworkPolicy у режимі default-deny обмежує, хто з ким говорить, з явними дозволами тільки на DNS і на вхід з ingress-контролера. ResourceQuota обмежує споживання. Плюс Argo AppProject обмежує, що взагалі може створити сам GitOps-контролер від імені тенанта.

**10. За замовчуванням у Kubernetes поди різних namespace можуть спілкуватися?**
Так. Namespace — це межа іменування і RBAC, а не мережева межа. Без NetworkPolicy будь-який под може звернутися до будь-якого іншого. Саме тому default-deny — перше, що я застосовую в тенантському namespace.

**11. Чому `maxUnavailable: 0`?**
Щоб під час rolling update ємність ніколи не падала нижче заявленої кількості реплік: новий под має стати Ready до видалення старого. У парі з `preStop` і `terminationGracePeriodSeconds` це дає розгортання без втрати запитів, бо видалення з endpoints встигає поширитися на всі вузли.

**12. Чим liveness відрізняється від readiness і чому в них різні налаштування?**
Readiness керує тим, чи йде на под трафік; liveness — чи перезапустити контейнер. Readiness агресивніша, бо зняти трафік дешево. Liveness консервативніша, бо рестарт дорогий. Критично: liveness не повинна залежати від зовнішніх сервісів, інакше падіння бази даних спричинить каскадні рестарти всіх подів.

**13. Як працює відкат?**
`git revert` коміту, який змінив тег образу. Argo CD синхронізує попередню версію протягом циклу реконсиляції. `kubectl rollout undo` теж працює миттєво, але з `selfHeal: true` Argo CD відкотить його назад, тому це аварійний варіант, після якого треба одразу зробити revert у Git.

**14. Чому образи пінуються за digest, а не за тегом?**
Тег — рухомий вказівник, той самий тег завтра може вказувати на інший образ. Digest незмінний. Це робить збірки відтворюваними. Ціна — ручне оновлення, яке в реальному проєкті автоматизує Renovate або Dependabot.

**15. Чому CI не має доступу до кластера?**
Це найважливіша межа безпеки в системі. CI виконує код із pull request-ів, зокрема від зовнішніх контрибʼюторів. Якщо він має креденшели кластера, шкідливий PR може отримати доступ до продакшену. Pull-модель повністю знімає цей клас атаки.

**16. Чому Helm, а не Kustomize?**
Kustomize простіший для накладання патчів і був би достатнім для цього проєкту. Helm обрано, бо він дає версіонування пакета, валідацію значень через JSON Schema і умовну логіку в шаблонах, а також тому, що вміння писати чарти — це те, що я хотіла продемонструвати. Для bootstrap Argo CD я використала саме Kustomize, бо там Helm додав би непотрібний стан.

**17. Що ти змінила б для реального продакшену?**
Argo CD у HA-конфігурації з кількома репліками. Керований кластер замість kind, регіональний, із вузлами в кількох зонах доступності. External Secrets Operator замість Sealed Secrets, щоб мати централізовану ротацію. Повний стек обсервабельності з логами і алертами. Argo Rollouts для canary-деплоїв з автоматичним аналізом. Kyverno або Gatekeeper для примусового застосування політик, а не тільки перевірки в CI. Renovate для автоматичного оновлення пінів.

**18. Як би ти масштабувала це на 50 тенантів?**
ApplicationSet із генератором по каталогах або по Git-файлах замість написання Application вручну. Спільна бібліотека Helm-чартів. Автоматизоване створення тенанта як шаблон із параметрами. І на певному масштабі — розділення на кілька кластерів з Argo CD, що керує ними всіма, бо ізоляція namespace має межу.

**19. Як ти дізнаєшся, що щось зламано?**
Зараз — через health status Applications в Argo CD і скрипт верифікації. Це усвідомлене обмеження: повна обсервабельність із алертами на симптоми і бюджетами помилок — окремий проєкт, і я не хотіла робити тут напівзаходи.

**20. Що виявилося найважчим?**
Порядок bootstrap. Спершу все падало, бо ресурси застосовувалися до створення CRD, від яких залежали. Sync waves вирішують це, але спочатку треба зрозуміти, що проблема саме в порядку, а не в самих маніфестах. Другий за складністю — конфлікт HPA і Argo CD за поле `replicas`, який виглядав як випадкове коливання кількості подів.

---

## 22. Складність і вартість

**Складність:** Advanced.

**Цінність для навчання:** найвища з чотирьох проєктів. Закриває GitOps, написання Helm-чартів, ingress і TLS, керування секретами, безпеку Kubernetes — п'ять прогалин одночасно.

**Вартість у хмарі:** $0 у базовій конфігурації.

| Ресурс | Вартість | Примітка |
|---|---|---|
| kind-кластер | $0 | Docker на твоєму ноутбуці |
| GitHub Actions | $0 | Безлімітно для публічних репозиторіїв |
| GHCR | $0 | Безкоштовно для публічних образів |
| TLS локально | $0 | Самопідписаний ClusterIssuer |
| **Опційно:** VM для публічного демо | ~€4/міс | Hetzner CX22, k3s |
| **Опційно:** домен | ~$10/рік | Або безкоштовний піддомен |
| **Опційно:** Cloudflare | $0 | Безкоштовний тариф достатній |

**Як мінімізувати вартість:** публічну частину роби в останню чергу і тільки на час зняття скріншотів, потім вимикай VM. Або взагалі використай Cloudflare Tunnel до локального kind — це дає публічний HTTPS-URL без жодної VM.

**Вимоги до заліза:** 8 ГБ RAM мінімум, 16 ГБ комфортно. Argo CD плюс платформні компоненти займають приблизно 2,5–3 ГБ. Якщо памʼяті бракує — зменш кластер до одного control-plane і одного worker і познач це в README як обмеження середовища розробки.

---

## 23. Місце в загальному порядку

Цей проєкт перший. Причини:

1. **Коштує нуль.** Можна почати сьогодні, без банківської картки і без ризику рахунку.
2. **Спирається на те, що ти вже вмієш.** Kubernetes-навантаження ти знаєш із дипломної. Тут ти піднімаєшся на рівень вище — до платформи.
3. **Закриває найчастіше згадувану прогалину.** Argo CD і GitOps фігурують у великій частині вакансій, і в тебе зараз нуль експозиції.
4. **Створює підґрунтя.** Проєкт C (обсервабельність) розгортається на цю саму платформу через Argo CD, і ти зможеш написати в README, що репозиторії композуються. Це рідкісний сигнал.

Навички, які він готує для наступних проєктів: розуміння декларативної моделі та реконсиляції знадобиться для Terraform у Проєкті B; Prometheus і ServiceMonitor тут — мінімальна версія того, що розгорнеться повністю в Проєкті C; NetworkPolicy і RBAC готують до розмови про IAM у хмарі.

---

## Що робити далі

1. Створи репозиторій і зроби Фазу 1 сьогодні. Це 30 хвилин.
2. Фази 2–4 за перший тиждень. У кінці тижня в тебе працює локальний кластер із зібраним образом.
3. Фази 5–6 за другий тиждень. У кінці — скріншот Argo CD із зеленим деревом. Це вже показуваний артефакт.
4. Фази 7–9 за третій-четвертий тиждень. Це основна інженерна робота.
5. Фази 10–13 за пʼятий-шостий тиждень. CI, демонстрації, документація.

Не відкладай документацію на кінець повністю: ADR пиши в момент прийняття рішення, поки памʼятаєш альтернативи, які відкинула. Потім вони не відновлюються.
