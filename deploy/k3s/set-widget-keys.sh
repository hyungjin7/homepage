#!/usr/bin/env bash
# 카드 위젯 키를 Secret homepage-secrets 에 넣는다(2026-11-26 실제 작업을 정리한 스크립트).
#
#   bash deploy/k3s/set-widget-keys.sh argocd grafana     # 고른 것만
#   bash deploy/k3s/set-widget-keys.sh                    # 4개 모두(빈 입력은 건너뜀)
#   bash deploy/k3s/set-widget-keys.sh --check            # 지금 들어 있는 키 이름·길이만
#
# 하는 일: 키 붙여 넣기(여러 줄 OK, 끝에 Enter → Ctrl+D) → 줄바꿈·공백·따옴표 제거 → 실제 API 로 시험(200 이어야 저장)
#          → Secret 에 그 키만 더함(다른 키는 그대로) → homepage 재시작 → ingress-cards.sh --apply(위젯 이름표).
# 키 값은 화면·파일에 남기지 않는다. 키 만드는 곳은 README "카드 위젯".
set -uo pipefail

NS=homepage
SECRET=homepage-secrets
cd "$(dirname "$0")"

# 이름|Secret 키|시험 주소|인증 머리말 앞부분|만드는 곳
TABLE='
argocd|HOMEPAGE_VAR_ARGOCD_KEY|https://argocd.delvrio.com/api/v1/applications|Authorization: Bearer |Argo CD › Settings › Accounts › homepage › Tokens › Generate New (eyJ…, 약 240자)
grafana|HOMEPAGE_VAR_GRAFANA_KEY|https://grafana.delvrio.com/api/prometheus/grafana/api/v1/alerts|Authorization: Bearer |Grafana › Administration › Service accounts › homepage(Viewer) › Add token (glsa_…)
gitea|HOMEPAGE_VAR_GITEA_KEY|https://gitea.delvrio.com/api/v1/user|Authorization: token |Gitea › 설정 › 애플리케이션 › 토큰 생성(read: repository·issue·notification)
n8n|HOMEPAGE_VAR_N8N_KEY|https://n8n.delvrio.com/api/v1/workflows?limit=1|X-N8N-API-KEY: |n8n › Settings › n8n API › Create API key
'

b64() { base64 | tr -d '\n'; }

show() {
  kubectl -n "$NS" get secret "$SECRET" -o go-template='{{range $k, $v := .data}}{{$k}} {{len $v}}{{"\n"}}{{end}}' 2>/dev/null |
    awk '{printf "  %-30s base64 %s자\n", $1, $2}'
}

if [ "${1:-}" = "--check" ]; then show; exit 0; fi

kubectl -n "$NS" get secret "$SECRET" >/dev/null 2>&1 ||
  kubectl -n "$NS" create secret generic "$SECRET" >/dev/null

names=("$@")
[ ${#names[@]} -eq 0 ] && names=(argocd grafana gitea n8n)

changed=0
for name in "${names[@]}"; do
  line=$(awk -F'|' -v n="$name" '$1==n {print; exit}' <<<"$TABLE")
  if [ -z "$line" ]; then echo "모름: $name (argocd grafana gitea n8n 중에서)"; continue; fi
  IFS='|' read -r _ key url header where <<<"$line"
  echo
  echo "== $name  ($where)"
  echo "   키를 붙여 넣고 Enter → Ctrl+D. 건너뛰려면 바로 Ctrl+D."
  val=$(cat | tr -d '\r\n\t "\\')
  if [ -z "$val" ]; then echo "   건너뜀"; continue; fi
  case "$val" in kubectl*|bash*|curl*) echo "   명령 글자가 들어옴(${val:0:8}…). 키를 다시 복사해서 실행하세요."; continue ;; esac
  code=$(curl -s -o /dev/null -w '%{http_code}' -H "${header}${val}" "$url")
  echo "   길이 ${#val}자, 시험 결과 HTTP $code"
  if [ "$code" != "200" ]; then
    echo "   저장 안 함 — 200 이 아님(401 = 키가 틀리거나 잘림). 키를 다시 만들어 보세요."
    continue
  fi
  kubectl -n "$NS" patch secret "$SECRET" --type merge \
    -p "{\"data\":{\"$key\":\"$(printf %s "$val" | b64)\"}}" >/dev/null && echo "   저장함 → $key" && changed=1
done

echo
echo "== 지금 Secret 키"
show
if [ "$changed" = 1 ]; then
  kubectl -n "$NS" rollout restart deploy/homepage >/dev/null && echo "homepage 재시작"
  bash ./ingress-cards.sh --apply 2>/dev/null | grep -B1 '위젯'
  echo "1분 뒤 화면 새로고침."
fi
