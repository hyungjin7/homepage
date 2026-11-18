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
