#!/usr/bin/env bash
# 이미 있는 Ingress 에 Homepage 이름표(gethomepage.dev/* 주석)를 붙인다.
# Homepage 는 이름표가 붙은 Ingress 를 스스로 찾아 카드로 보여 준다(config/kubernetes.yaml ingress: true).
#
#   bash ingress-cards.sh            # 미리보기(바꾸지 않음)
#   bash ingress-cards.sh --apply    # 이름표 붙이기(여러 번 해도 안전, --overwrite)
#   bash ingress-cards.sh --remove   # 이름표 떼기
#
# Ingress 는 "주소(host) + 경로" 로 찾는다(이름·namespace 를 몰라도 됨). 경로는 그 Ingress 에 있어야 하는 경로다.
# kubectl annotate 로 붙인 주석은 나중에 매니페스트를 kubectl apply 해도 지워지지 않는다.
# 새 앱은 이 표에 줄을 더하지 말고 그 앱 Ingress 매니페스트에 주석을 직접 단다(README "새 서비스 올리기").
set -euo pipefail
MODE="${1:-preview}"

# 주소|찾을 경로|카드 이름|그룹|아이콘|설명|순서|열 주소(비우면 https://주소)
# 그룹 순서 Customer → Develop → Cloud → Link, 그룹 안 순서 = 순서 칸(작을수록 앞). GitHub(Link 20)는 config/services.yaml.
CARDS='
homepage.delvrio.com|/|Homepage|Customer|homepage.png|이 화면|10|
bible.delvrio.com|/|말씀 스와이프|Customer|mdi-book-open-variant|틱톡처럼 넘겨 보는 성경 (개역한글)|20|
slp.delvrio.com|/|그린로직스|Customer|mdi-truck-outline|운송내역 관리 (SLP)|30|https://gl.delvrio.com
crm.delvrio.com|/|CRM|Customer|mdi-account-group-outline|TNC CRM|40|
suntax.delvrio.com|/|Suntax|Customer|mdi-calculator-variant-outline|세무 업무 (자체 로그인)|50|
www.delvrio.com|/|홈페이지|Customer|mdi-web|Delve 회사 홈페이지|60|
bbb.delvrio.com|/|bbb|Develop|mdi-robot-outline|중앙 운영 · AI|10|
ccc.delvrio.com|/|ccc|Develop|mdi-shield-check-outline|CSAP · AutoResearch · Agent|20|
chat.delvrio.com|/|Chat|Develop|rocket-chat.png|Rocket.Chat · SSO 바로 연결|30|https://chat.delvrio.com/oauth/keycloak
dashboard.delvrio.com|/|Dashboard|Develop|mdi-view-dashboard-outline|예약 작업 · GPU · 운영|40|
dify.delvrio.com|/|Dify|Develop|dify.png|AI 워크플로 · SSO 안됨(자체 로그인)|50|
moa.delvrio.com|/|MoA|Develop|mdi-book-open-page-variant-outline|설계 문서|70|
nextcloud.delvrio.com|/|NextCloud|Develop|nextcloud.png|파일 공유|80|
odysseus.delvrio.com|/|Odysseus|Develop|mdi-sail-boat|AI 작업실|90|
n8n.delvrio.com|/|n8n|Develop|n8n.png|자동화 워크플로|100|
grafana.delvrio.com|/|Grafana|Cloud|grafana.png|그래프 · GPU 기록|10|
prometheus.delvrio.com|/|Prometheus|Cloud|prometheus.png|지표 수집|20|
k8s.delvrio.com|/|Kubernetes|Cloud|kubernetes.png|Headlamp (회사에서만)|30|
gitea.delvrio.com|/|Gitea|Cloud|gitea.png|빌드 · 배포|40|
argocd.delvrio.com|/|Argo CD|Cloud|argo-cd.png|배포 상태|50|
sso.delvrio.com|/admin|Keycloak|Cloud|keycloak.png|로그인 관리 (회사에서만)|60|https://sso.delvrio.com/admin/master/console/
ai.delvrio.com|/|Open WebUI|Link|open-webui.png|AI 채팅 · 삭제 예정|10|
omlx.delvrio.com|/|oMLX|Link|mdi-brain|로컬 LLM 서버|30|https://omlx.delvrio.com/admin
'

# 클러스터의 Ingress 를 "namespace 이름 주소 경로" 줄로 펼친다(규칙·경로마다 한 줄).
LIST=$(kubectl get ingress -A -o go-template='{{range $i := .items}}{{range $r := $i.spec.rules}}{{if $r.http}}{{range $p := $r.http.paths}}{{$i.metadata.namespace}} {{$i.metadata.name}} {{$r.host}} {{$p.path}}{{"\n"}}{{end}}{{end}}{{end}}{{end}}')

missing=0
used=' '
while IFS='|' read -r host path name group icon desc weight href; do
  [ -z "$host" ] && continue
  # 같은 주소·경로를 가진 Ingress 중 첫 번째. "/" 를 찾을 때 "/" 가 없으면 그 주소의 첫 Ingress.
  hit=$(awk -v h="$host" -v p="$path" '$3==h && $4==p {print $1" "$2; exit}' <<<"$LIST")
  if [ -z "$hit" ] && [ "$path" = "/" ]; then
    hit=$(awk -v h="$host" '$3==h {print $1" "$2; exit}' <<<"$LIST")
  fi
  if [ -z "$hit" ]; then
    echo "  없음    $name ($host$path) — 이 주소의 Ingress 가 클러스터에 없다"; missing=$((missing+1)); continue
  fi
  ns=${hit% *}; ing=${hit#* }
  # 한 Ingress 에 주소가 여럿이면 카드는 하나만 — 먼저 나온 줄이 이긴다.
  case "$used" in *" $ns/$ing "*) echo "  건너뜀  $name — $ns/$ing 는 이미 다른 카드에 씀"; continue ;; esac
  used="$used$ns/$ing "
  [ -z "$href" ] && href="https://$host"
  # Health checks must not start OAuth transactions.
  monitor="$href"
  if [ "$host" = "chat.delvrio.com" ]; then monitor="https://$host"; fi
  case "$MODE" in
    --apply)
      kubectl -n "$ns" annotate ingress "$ing" --overwrite \
        gethomepage.dev/enabled=true gethomepage.dev/external=true \
        gethomepage.dev/name="$name" gethomepage.dev/group="$group" gethomepage.dev/icon="$icon" \
        gethomepage.dev/description="$desc" gethomepage.dev/weight="$weight" \
        gethomepage.dev/href="$href" gethomepage.dev/siteMonitor="$monitor" >/dev/null
      echo "  붙임    $name → $ns/$ing" ;;
    --remove)
      kubectl -n "$ns" annotate ingress "$ing" gethomepage.dev/enabled- gethomepage.dev/external- \
        gethomepage.dev/name- gethomepage.dev/group- gethomepage.dev/icon- gethomepage.dev/description- \
        gethomepage.dev/weight- gethomepage.dev/href- gethomepage.dev/siteMonitor- >/dev/null 2>&1 || true
      echo "  뗌      $name → $ns/$ing" ;;
    *)
      echo "  미리보기 $name → $ns/$ing ($href)" ;;
  esac
done <<<"$CARDS"

# 표에서 뺀 카드: 클러스터 Ingress 에 남은 이름표를 --apply 때 뗀다(카드 이름으로 찾음).
REMOVED='Workspace MCP Netdata Flower OpenClaw'
for gone in $REMOVED; do
  kubectl get ingress -A --no-headers \
    -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,CARD:.metadata.annotations.gethomepage\.dev/name' |
  awk -v c="$gone" '$3==c {print $1" "$2}' | while read -r ns ing; do
    if [ "$MODE" = "--apply" ] || [ "$MODE" = "--remove" ]; then
      kubectl -n "$ns" annotate ingress "$ing" gethomepage.dev/enabled- gethomepage.dev/external- \
        gethomepage.dev/name- gethomepage.dev/group- gethomepage.dev/icon- gethomepage.dev/description- \
        gethomepage.dev/weight- gethomepage.dev/href- gethomepage.dev/siteMonitor- >/dev/null 2>&1 || true
      echo "  뗌      $gone (표에서 뺀 카드) → $ns/$ing"
    else
      echo "  뗄 예정 $gone (표에서 뺀 카드) → $ns/$ing"
    fi
  done
done

# 주소를 옮긴 옛 Ingress 의 이름표 떼기(같은 카드 이름이 새 Ingress 에도 있어 이름으로는 못 찾고 주소로 찾는다).
# i3.delvrio.com → iii.delvrio.com(2026-11-25). 새 iii 카드는 iii 저장소 deploy/k3s/ingress-frontend.yaml 이름표로 나온다.
REMOVED_HOSTS='i3.delvrio.com'
for gone in $REMOVED_HOSTS; do
  awk -v h="$gone" '$3==h {print $1" "$2}' <<<"$LIST" | sort -u | while read -r ns ing; do
    if [ "$MODE" = "--apply" ] || [ "$MODE" = "--remove" ]; then
      kubectl -n "$ns" annotate ingress "$ing" gethomepage.dev/enabled- gethomepage.dev/external- \
        gethomepage.dev/name- gethomepage.dev/group- gethomepage.dev/icon- gethomepage.dev/description- \
        gethomepage.dev/weight- gethomepage.dev/href- gethomepage.dev/siteMonitor- >/dev/null 2>&1 || true
      echo "  뗌      옛 주소 $gone → $ns/$ing"
    else
      echo "  뗄 예정 옛 주소 $gone → $ns/$ing"
    fi
  done
done

echo "Ingress 를 못 찾은 카드: ${missing}개"
[ "$MODE" = "preview" ] && echo "바꾸려면: bash $0 --apply"
exit 0
