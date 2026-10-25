#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
umask 077
mkdir -p local-students/supabase/migrations artifacts config
if [ ! -f local-students/supabase/config.toml ]; then
  cp supabase/config.toml local-students/supabase/config.toml
fi
cp supabase/migrations/20261024000100_student_core.sql local-students/supabase/migrations/
./scripts/supabase.sh start --workdir local-students -x vector,logflare,edge-runtime,imgproxy,supavisor,realtime > artifacts/student-backend-start.log 2>&1
./scripts/supabase.sh migration up --local --workdir local-students
./scripts/supabase.sh status --workdir local-students -o json 2>/dev/null | python3 -c 'import json,sys,pathlib;s=json.load(sys.stdin);p=pathlib.Path("config/student-local.json");p.write_text(json.dumps({"SUPABASE_URL":s["API_URL"],"SUPABASE_ANON_KEY":s.get("ANON_KEY") or s["PUBLISHABLE_KEY"]},indent=2));p.chmod(0o600);print("Tasko Students API:",s["API_URL"])'
