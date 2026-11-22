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

## 설정 바꾸기
`config/*.yaml` 을 고치고 같은 `kubectl apply -k` 를 다시 하면 Pod 가 저절로 새로 뜬다.
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
  gethomepage.dev/group: Develop           # Customer | Develop | Cloud | ai
  gethomepage.dev/icon: mdi-apps           # https://pictogrammers.com/library/mdi/ 또는 xxx.png
  gethomepage.dev/description: 한 줄 설명
  gethomepage.dev/siteMonitor: https://새앱.delvrio.com
  # 첫 화면 주소가 "/" 가 아니면: gethomepage.dev/href: https://새앱.delvrio.com/admin
  ```
- 클러스터 Ingress 가 없는 바깥 사이트(GitHub 등)만 `config/services.yaml` 에 적는다.

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
