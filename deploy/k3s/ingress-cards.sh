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
CARDS='
bbb.delvrio.com|/|BBB|델브 업무|mdi-robot-outline|중앙 운영 · AI|10|
i3.delvrio.com|/|i3|델브 업무|mdi-chart-line|투자 화면|20|
slp.delvrio.com|/|그린로직스|고객|mdi-truck-outline|운송내역 관리 (SLP)|30|https://gl.delvrio.com
ccc.delvrio.com|/|ccc|델브 업무|mdi-shield-check-outline|CSAP · AutoResearch · Agent|40|
crm.delvrio.com|/|CRM|델브 업무|mdi-account-group-outline|TNC CRM|50|
chat.delvrio.com|/|Chat|델브 업무|rocket-chat.png|Rocket.Chat|60|
nextcloud.delvrio.com|/|NextCloud|델브 업무|nextcloud.png|파일 공유|70|
suntax.delvrio.com|/|Suntax|고객|mdi-calculator-variant-outline|세무 업무 (자체 로그인)|80|
www.delvrio.com|/|홈페이지|델브 업무|mdi-web|Delve 회사 홈페이지|90|
dashboard.delvrio.com|/|Dashboard|운영 · 모니터링|mdi-view-dashboard-outline|예약 작업 · GPU · 운영|10|
grafana.delvrio.com|/|Grafana|운영 · 모니터링|grafana.png|그래프 · GPU 기록|20|
prometheus.delvrio.com|/|Prometheus|운영 · 모니터링|prometheus.png|지표 수집|30|
k8s.delvrio.com|/|Kubernetes|운영 · 모니터링|kubernetes.png|Headlamp (회사에서만)|40|
flower.delvrio.com|/|Flower|운영 · 모니터링|mdi-flower-outline|Celery 작업 (11-27 까지)|50|
gitea.delvrio.com|/|Gitea|운영 · 모니터링|gitea.png|빌드 · 배포|60|
argocd.delvrio.com|/|Argo CD|운영 · 모니터링|argo-cd.png|배포 상태|70|
netdata.delvrio.com|/|Netdata|운영 · 모니터링|netdata.png|서버 실시간 상태|80|
sso.delvrio.com|/admin|Keycloak|운영 · 모니터링|keycloak.png|로그인 관리 (회사에서만)|90|https://sso.delvrio.com/admin/master/console/
dify.delvrio.com|/|Dify|AI · 개발|dify.png|AI 워크플로|10|
omlx.delvrio.com|/|oMLX|AI · 개발|mdi-brain|로컬 LLM 서버|20|https://omlx.delvrio.com/admin
odysseus.delvrio.com|/|Odysseus|AI · 개발|mdi-sail-boat|AI 작업실|30|
n8n.delvrio.com|/|n8n|AI · 개발|n8n.png|자동화 워크플로|40|
ai.delvrio.com|/|Open WebUI|AI · 개발|open-webui.png|AI 채팅|50|
openclaw.delvrio.com|/|OpenClaw|AI · 개발|mdi-robot-excited-outline|AI 에이전트|60|
moa.delvrio.com|/|MoA|AI · 개발|mdi-book-open-page-variant-outline|설계 문서|70|
mcp.delvrio.com|/youtube|MCP|AI · 개발|mdi-connection|MCP 서버 (YouTube 조회)|80|https://mcp.delvrio.com/youtube
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
  case "$MODE" in
    --apply)
      kubectl -n "$ns" annotate ingress "$ing" --overwrite \
        gethomepage.dev/enabled=true gethomepage.dev/external=true \
        gethomepage.dev/name="$name" gethomepage.dev/group="$group" gethomepage.dev/icon="$icon" \
        gethomepage.dev/description="$desc" gethomepage.dev/weight="$weight" \
        gethomepage.dev/href="$href" gethomepage.dev/siteMonitor="$href" >/dev/null
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

echo "Ingress 를 못 찾은 카드: ${missing}개"
[ "$MODE" = "preview" ] && echo "바꾸려면: bash $0 --apply"
exit 0
