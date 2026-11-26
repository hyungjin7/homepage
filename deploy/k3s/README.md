# Homepage — 사내 바로가기 대시보드 (homepage.delvrio.com)

원본 [gethomepage/homepage](https://github.com/gethomepage/homepage) 공식 이미지(`ghcr.io/gethomepage/homepage:v2.8.0`)를 그대로 쓴다.
이 포크에는 **k3s 설치 파일과 설정만** 더했다(원본 코드는 안 고침 → 원본 따라잡기 때 충돌 없음).

## 구성
| 파일 | 내용 |
|---|---|
| `00-namespace.yaml` | namespace `homepage` |
| `01-rbac.yaml` | 쿠버네티스 위젯용 **읽기 전용** 권한(get/list 만) |
| `02-app.yaml` | Deployment·Service(포트 3000). DB·PVC 없음. `/app/config` 는 쓰기 가능한 emptyDir 이고 시작할 때 ConfigMap 을 복사해 넣는다 |
| `03-sso-ingress.yaml` | 델브 로그인(forwardAuth) + Ingress `homepage.delvrio.com`(letsencrypt-prod). 회사 전용 문(`homepage-lan`)은 만들어만 두고 꺼 둠 |
| `ingress-cards.sh` | 기존 Ingress 에 Homepage 이름표를 붙인다(미리보기 기본, `--apply`, `--remove`) |
| `config/*.yaml` | 화면 설정(서비스 카드·위젯·북마크). kustomize 가 ConfigMap 으로 만든다 |
| `secrets.example.yaml` | 위젯 키 예시(적용 안 함) |

## 들어가는 길
1. Traefik 이 요청마다 bbb dcore 에 쿠키(`dlv_sso`)를 묻는다 → 로그인 안 됐으면 login.delvrio.com 으로.
2. 권한 = bbb `navigation_apps` 의 `homepage` 행(그룹 `homepage`, 처음엔 ceo, superuser 는 항상). 사람 추가는 bbb Admin › 그룹 `homepage`.
   (bbb 쪽 행·그룹·CSRF 는 bbb 저장소 PR 로 들어간다.)
3. Homepage 자체 로그인은 끈다(`HOMEPAGE_AUTH_ENABLED=false`).

## 설치 (alpha 에서, 한 번)
```bash
cd ~/projects && git clone https://github.com/hyungjin7/homepage.git   # 이미 있으면 git -C homepage pull
kubectl apply -k homepage/deploy/k3s
kubectl -n homepage rollout status deploy/homepage
```
DNS 는 `*.delvrio.com` 와일드카드라 따로 할 일이 없다. 인증서는 cert-manager 가 몇 분 안에 발급한다(`kubectl -n homepage get certificate`).

## 자동 배포 (Argo CD, 2026-11-26)
GitHub `dev`에 커밋된 `deploy/k3s`를 Argo CD Application `homepage`가 자동 배포한다.
공식 고정 이미지와 기존 설정 파일을 그대로 사용하며, 설정 변경으로 ConfigMap 이름이 달라지면 Pod가 교체된다.

- GitHub의 Gitea 동기화 워크플로우는 유지한다. Gitea CI는 렌더링·설정·배포 범위만 검증하며 클러스터에 쓰지 않는다.
- 공개 GitHub 저장소를 직접 읽으므로 Argo CD에 저장소 토큰을 추가하지 않는다.
- 최초 등록: `kubectl apply -f deploy/argocd/homepage.yaml`.
- 자동 삭제(prune)는 끈다. 삭제된 파일에 해당하는 리소스와 오래된 ConfigMap은 검토 후 별도로 정리한다.
- Secret `homepage-secrets`와 인증서 Secret은 관리 대상이 아니다. 기존 값을 유지한다.
- 다른 앱의 카드 이름표 수정은 `bash deploy/k3s/ingress-cards.sh` 미리보기 후 `--apply`로 수동 실행한다.
- 이전에 삭제한 업스트림 GitHub 워크플로우는 이번 작업에서 복구하거나 추가 변경하지 않았다.

검증: `kubectl kustomize deploy/k3s > .homepage-rendered.yaml`,
`python deploy/k3s/validate_gitops.py .homepage-rendered.yaml`,
`python -m unittest discover -s deploy/k3s/tests -v` (PyYAML 필요).

배포 확인: `kubectl -n argocd get application homepage`의 Synced/Healthy와
`kubectl -n homepage rollout status deploy/homepage`를 확인한다.
CI 검증과 Argo CD 배포는 독립 실행이므로 Gitea CI 성공 자체가 배포 성공은 아니다.

복구: 자동 동기화를 먼저 끄고(`kubectl -n argocd patch application homepage --type=merge -p '{"spec":{"syncPolicy":{"automated":null}}}'`),
GitHub `dev`의 문제가 된 설정을 revert한다. 정상 설정 확인 후 자동 동기화를 다시 켠다.
Application 삭제 시 리소스를 함께 지우는 finalizer는 설정하지 않는다.

## 설정 바꾸기
`deploy/k3s/config/*.yaml`을 수정해 GitHub `dev`에 커밋하면 Argo CD가 적용하고 Pod가 저절로 새로 뜬다.
- 서비스 카드: `config/services.yaml` · 안내 https://gethomepage.dev/configs/services/
- 위젯 키 같은 비밀 값: 저장소에 넣지 않는다. Secret 을 만들고 설정에서 `{{HOMEPAGE_VAR_이름}}` 으로 쓴다.
  ```bash
  kubectl -n homepage create secret generic homepage-secrets \
    --from-literal=HOMEPAGE_VAR_GRAFANA_PASSWORD='...' --dry-run=client -o yaml | kubectl apply -f -
  kubectl -n homepage rollout restart deploy/homepage
  ```
- 이 저장소는 공개 포크라 **내부 IP·클러스터 내부 주소·키는 커밋하지 않는다.**

## 카드 자동 등록 (Ingress 이름표)
Homepage 는 이름표가 붙은 Ingress 를 스스로 찾아 카드로 만든다(`config/kubernetes.yaml` `ingress: true`). 이름표가 없는 Ingress 는 안 나온다.
- 지금 있는 사이트: `bash deploy/k3s/ingress-cards.sh` 로 미리 보고 `--apply`. 주소+경로로 Ingress 를 찾으니 이름을 몰라도 된다. 표에 없거나 클러스터에 없는 주소는 "없음"으로 알려 준다.
- **새 서비스 올리기**: 그 앱 Ingress 매니페스트 `metadata.annotations` 에 아래를 더하면 apply 하는 순간 카드가 생긴다.
  ```yaml
  gethomepage.dev/enabled: "true"
  gethomepage.dev/external: "true"        # Pod 상태 표시 안 함(이름표 규칙이 앱마다 달라서)
  gethomepage.dev/name: 새앱
  gethomepage.dev/group: Develop           # Customer | Develop | Cloud
  gethomepage.dev/icon: mdi-apps           # https://pictogrammers.com/library/mdi/ 또는 xxx.png
  gethomepage.dev/description: 한 줄 설명
  gethomepage.dev/siteMonitor: https://새앱.delvrio.com
  # 첫 화면 주소가 "/" 가 아니면: gethomepage.dev/href: https://새앱.delvrio.com/admin
  ```
- 클러스터 Ingress 가 없는 바깥 사이트(GitHub 등)만 `config/services.yaml` 에 적는다.

## 카드 위젯 · 날씨 (2026-11-26)
- 날씨: 맨 위 줄 "인천"(OpenMeteo, `config/widgets.yaml`). 키 필요 없음.
- GPU 카드(Cloud): `config/services.yaml` 의 Prometheus 지표 4개(studio 온도·전력, alpha-98 온도·사용률). Secret 에 `HOMEPAGE_VAR_PROMETHEUS_URL`(클러스터 안 Prometheus 주소) 필요.
- Argo CD·Gitea 카드 안 숫자: `ingress-cards.sh` 의 `WIDGETS` 표. Secret 에 키가 있을 때만 `--apply` 가 위젯을 붙인다.

| Secret 키 | 값 |
|---|---|
| `HOMEPAGE_VAR_PROMETHEUS_URL` | 클러스터 안 Prometheus 주소(bbb `services/rag` 의 `RAG_PROMETHEUS_URL` 과 같은 값) |
| `HOMEPAGE_VAR_ARGOCD_KEY` | Argo CD 읽기 전용 계정 `homepage` 의 API 토큰 |
| `HOMEPAGE_VAR_GITEA_KEY` | Gitea 토큰(read: repository·issue·notification) |

Secret 은 `kubectl -n homepage patch secret homepage-secrets --type merge -p '{"stringData":{"키":"값"}}'`(없으면 `create secret generic`)로 넣고 `kubectl -n homepage rollout restart deploy/homepage`.

## 화면 배치 고치기 (직접 편집)
| 바꾸고 싶은 것 | 고칠 곳 | 적용 |
|---|---|---|
| 그룹 순서·열 수 | `config/settings.yaml` `layout` (적은 순서 = 위에서부터) | `kubectl apply -k deploy/k3s` |
| 카드의 그룹·이름·아이콘·설명·순서 | `ingress-cards.sh` 표의 그 줄 (그룹 칸, 순서 칸 = 작을수록 앞) | `bash deploy/k3s/ingress-cards.sh --apply` |
| 바깥 사이트 카드(GitHub 등) | `config/services.yaml` | `kubectl apply -k deploy/k3s` |

- **끌어서 옮기기**: 화면 오른쪽 아래 "배치 편집" → 그룹 제목줄·카드를 끌어 같은 줄 안에서 옮김 → "완료"(`config/custom.js`·`custom.css`). 순서는 그 브라우저에만 저장됨. 모두에게 같게 하려면 "설정 복사" 내용대로 위 표의 파일을 고친다. "처음대로"는 브라우저 저장을 지움.
- 새 그룹을 만들면 `settings.yaml` `layout` 에도 같은 이름을 적는다(글자·띄어쓰기까지 같아야 함). 카드가 0개인 그룹은 화면에 안 나온다.
- 급할 때 한 장만: `kubectl -n <ns> annotate ingress <이름> --overwrite gethomepage.dev/group=Develop` (표도 같이 고쳐 둔다. 안 그러면 다음 `--apply` 때 표 값으로 돌아감).

## 회사에서만 열기(선택)
`03-sso-ingress.yaml` Ingress 의 `router.middlewares` 를
`homepage-homepage-lan@kubernetescrd,homepage-homepage-sso@kubernetescrd` 로 바꾸고 다시 apply.

## 버전 올리기
`02-app.yaml` 의 이미지 태그만 바꾸고 apply.

## 되돌리기
```bash
kubectl delete -k homepage/deploy/k3s
```
Traefik 진입 설정(HelmChartConfig 등)은 건드리지 않는다. Middleware·Ingress 만 더하고 지운다.


### Develop SSO 진입 (2026-11-25, AI 도움으로 수정)

Chat 카드는 Rocket.Chat 공식 `/oauth/keycloak` 진입점을 사용한다. 기존 Keycloak 세션으로 로그인하며,
직접 `/` 주소를 열면 제품의 로그인 버튼이 표시될 수 있다. 상태 점검(siteMonitor)은 `/`를 사용해
OAuth 요청을 반복 생성하지 않는다. Dify 현재 설치본은 자체 로그인으로 SSO 안됨을 카드에 표시한다.
