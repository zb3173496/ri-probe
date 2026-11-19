#!/bin/bash
# Webnovel 蛊真人章评批量抓取编排器 —— 5 路并行，坏 IP 自动换 runner
export GH_TOKEN=$(python3 -c "import json; print(json.load(open('/tmp/ri/token.json'))['access_token'])")
REPO=zb3173496/ri-probe
RUN=/tmp/ri/wn-run
mkdir -p $RUN/dl $RUN/log
BATCH=30
TOTAL=2334

worker() {
  local name=$1 start=$2 end=$3
  local cur=$start
  while [ $cur -lt $end ]; do
    local cnt=$BATCH
    if [ $((cur + BATCH)) -gt $end ]; then cnt=$((end - cur)); fi
    echo "[$name] trigger start=$cur count=$cnt $(date +%H:%M:%S)"
    gh workflow run wn-comments.yml --repo $REPO -f start=$cur -f count=$cnt > /dev/null 2>&1
    sleep 20
    local rid=$(gh run list --repo $REPO --workflow=wn-comments.yml --limit 1 --json databaseId --jq '.[0].databaseId')
    gh run watch $rid --repo $REPO --interval 45 > /dev/null 2>&1
    rm -rf $RUN/dl/$name
    gh run download $rid --repo $REPO --dir $RUN/dl/$name > /dev/null 2>&1
    local f=$RUN/dl/$name/wn-comments-$cur/comments.json
    if [ -f "$f" ]; then
      local nxt=$(python3 -c "import json; print(json.load(open('$f'))['nextStart'])" 2>/dev/null || echo $cur)
      local done=$(python3 -c "import json; print(len(json.load(open('$f'))['chapters']))" 2>/dev/null || echo 0)
      echo "[$name] batch done=$done next=$nxt $(date +%H:%M:%S)"
      if [ "$done" -gt 0 ]; then
        cp "$f" $RUN/log/wn-$cur.json
      fi
      if [ "$nxt" = "$cur" ]; then
        echo "[$name] bad IP, retry with new runner"
        sleep 30
      fi
      cur=$nxt
    else
      echo "[$name] no artifact, retry $(date +%H:%M:%S)"
      sleep 60
    fi
    sleep 5
  done
  echo "[$name] FINISHED range $start-$end"
}

worker A 0 467 &
worker B 467 934 &
worker C 934 1401 &
worker D 1401 1868 &
worker E 1868 2334 &
wait
echo "ALL WORKERS DONE"
python3 - << 'EOF'
import json, glob
master = {}
for f in sorted(glob.glob('/tmp/ri/wn-run/log/wn-*.json')):
    d = json.load(open(f))
    master.update(d.get('chapters', {}))
json.dump(master, open('/tmp/ri/wn-run/master.json', 'w'), ensure_ascii=False)
tot = sum(len(v['reviews']) for v in master.values())
print('MASTER chapters:', len(master), 'reviews:', tot)
EOF
