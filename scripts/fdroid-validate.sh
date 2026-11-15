#!/usr/bin/env bash
# Checks docs/fdroid/<appid>.yml the way fdroiddata's GitLab pipeline does,
# inside the F-Droid buildserver image. See docs/DISTRIBUTION.md (F-Droid).
#
#   scripts/fdroid-validate.sh lint            lint, rewritemeta, checkupdates
#   scripts/fdroid-validate.sh build           `fdroid build` of the latest entry,
#                                              checked against its release APK
#   scripts/fdroid-validate.sh rehearse <apk>  `fdroid build` of HEAD (must be
#                                              pushed), checked against <apk>:
#                                              HEAD built the release.yml way
#
# Needs Docker. The image is amd64 only; on Apple Silicon enable Rosetta in
# Docker Desktop. The unsigned APK is copied to build/fdroid/.
set -euo pipefail

APPID=org.motherofallvpns.moavdeploy
IMAGE=registry.gitlab.com/fdroid/fdroidserver:buildserver-trixie
MODE=${1:-lint}

if [ ! -f /etc/profile.d/bsenv.sh ]; then
  # Host side: re-run this script in the buildserver image. The named volume
  # caches fdroidserver, the Flutter srclib and Gradle between runs.
  ROOT=$(cd "$(dirname "$0")/.." && pwd)
  mkdir -p "$ROOT/build/fdroid"
  if [ "$MODE" = rehearse ]; then
    cp "${2:?usage: fdroid-validate.sh rehearse <apk>}" "$ROOT/build/fdroid/reference.apk"
    REHEARSE_COMMIT=$(git -C "$ROOT" rev-parse HEAD)
    REHEARSE_VERSION=$(sed -n 's/^version: //p' "$ROOT/pubspec.yaml")
    export REHEARSE_COMMIT REHEARSE_VERSION
  fi
  exec docker run --rm --platform linux/amd64 \
    -e REHEARSE_COMMIT -e REHEARSE_VERSION \
    -v fdroid-validate-home:/home/vagrant \
    -v "$ROOT/docs/fdroid:/recipe:ro" \
    -v "$ROOT/scripts/fdroid-validate.sh:/fdroid-validate.sh:ro" \
    -v "$ROOT/build/fdroid:/out" \
    "$IMAGE" bash /fdroid-validate.sh "$MODE"
fi

# Container side.
source /etc/profile.d/bsenv.sh
if [ ! -d "$fdroidserver/.git" ]; then
  rm -rf "$fdroidserver"
  git clone -q --depth 1 https://gitlab.com/fdroid/fdroidserver.git "$fdroidserver"
else
  git -C "$fdroidserver" pull -q --ff-only || true
fi
export PATH="$fdroidserver:$PATH" PYTHONPATH="$fdroidserver:$fdroidserver/examples"
export PYTHONUNBUFFERED=true serverwebroot=/tmp
echo "fdroidserver $(git -C "$fdroidserver" log -1 --format='%h %cs')"

# A small fdroiddata tree: its real config and srclibs, plus our recipe.
DATA=/work/fdroiddata
git clone -q --depth 1 --filter=blob:none --sparse https://gitlab.com/fdroid/fdroiddata.git "$DATA"
cd "$DATA"
git sparse-checkout set --no-cone /config.yml /config/ /srclibs/flutter.yml
mkdir -p metadata
cp "/recipe/$APPID.yml" metadata/
git add --sparse "metadata/$APPID.yml"
git -c user.email=fdroid@localhost -c user.name=fdroid commit -qm "recipe under test"
chmod 0600 config.yml
VC=$(sed -n 's/^CurrentVersionCode: //p' "metadata/$APPID.yml")

if [ "$MODE" = lint ]; then
  fdroid lint "$APPID"
  fdroid rewritemeta "$APPID"
  git diff --exit-code -- "metadata/$APPID.yml" ||
    { echo "FAIL: rewritemeta changed the recipe (diff above)."; exit 1; }
  fdroid checkupdates --auto "$APPID"
  git diff --exit-code -- "metadata/$APPID.yml" ||
    { echo "FAIL: checkupdates changed the recipe (diff above)."; exit 1; }
  echo "OK: lint, rewritemeta and checkupdates are clean for $APPID:$VC."
  exit 0
fi

if [ "$MODE" = rehearse ]; then
  # Aim the latest entry at the commit under test. Nothing is published for
  # it yet, so the comparison with the reference APK happens at the end.
  VC=${REHEARSE_VERSION#*+}
  python3 - "metadata/$APPID.yml" "$REHEARSE_COMMIT" "${REHEARSE_VERSION%+*}" "$VC" <<'EOF'
import sys
from ruamel.yaml import YAML

path, commit, name, code = sys.argv[1:]
yaml = YAML()
yaml.width = 4096
with open(path) as f:
    app = yaml.load(f)
build = app["Builds"][-1]
build.update(commit=commit, versionName=name, versionCode=int(code))
app["Builds"] = [build]
app.update(CurrentVersion=name, CurrentVersionCode=int(code))
del app["Binaries"]
with open(path, "w") as f:
    yaml.dump(app, f)
EOF
elif [ "$VC" -le 19 ]; then
  # v0.2.16 (19) predates the reproducibility fixes and can never match its
  # release APK, so it is only built. Later versions are verified by fdroid.
  sed -i '/^Binaries:/,/^$/d' "metadata/$APPID.yml"
fi

# Build as the unprivileged vagrant user, as the buildserver does.
sdkmanager "platform-tools" "build-tools;31.0.0" >/dev/null
apt-get -qq update >/dev/null
apt-get -qq install -y sudo openjdk-21-jdk-headless >/dev/null
mkdir -p "$home_vagrant/.android" "$home_vagrant/.gradle" "$home_vagrant/metadata" \
  "$home_vagrant/build" "$DATA/tmp"
cp "metadata/$APPID.yml" "$home_vagrant/metadata/"
ln -sfn "$DATA/tmp" "$home_vagrant/tmp"
ln -sfn "$DATA/srclibs" "$home_vagrant/srclibs"
chown -R vagrant "$home_vagrant" "$DATA"
run_fdroid() {
  sudo --user vagrant env PATH="$PATH" PYTHONPATH="$PYTHONPATH" PYTHONUNBUFFERED=true \
    HOME="$home_vagrant" ANDROID_HOME="$ANDROID_HOME" GRADLE_USER_HOME="$home_vagrant/.gradle" \
    fdroid "$@"
}
cd "$home_vagrant"
ln -sfn "$DATA" "$home_vagrant/fdroiddata"
run_fdroid fetchsrclibs "$APPID:$VC" --verbose
rm -f "$home_vagrant/fdroiddata"
run_fdroid build --verbose --test --refresh-scanner --on-server --no-tarball "$APPID:$VC"
cp -f "$home_vagrant/tmp/${APPID}_${VC}.apk" /out/
sha256sum "/out/${APPID}_${VC}.apk"
echo "OK: fdroid build passed for $APPID:$VC; unsigned APK in build/fdroid/."

# Reproducibility: compare with the reference APK the way `fdroid build` does
# when Binaries is set (copy its signature onto our APK, then verify it).
REF=/out/reference.apk
if [ "$MODE" != rehearse ]; then
  VN=$(sed -n 's/^CurrentVersion: //p' "$DATA/metadata/$APPID.yml")
  REF=/tmp/release.apk
  RELEASE_APK=https://github.com/MotherofallVPNs/moav-deploy-app/releases/download/v$VN/app-release.apk
  if ! curl -fsSL -o "$REF" "$RELEASE_APK"; then
    echo "No release APK at $RELEASE_APK; skipped the comparison."
    exit 0
  fi
fi
entries() { unzip -v "$1" | awk '$7 ~ /^[0-9a-f]{8}$/ {print $7, $8}' | sort -k2; }
diff <(entries "$REF") <(entries "/out/${APPID}_${VC}.apk") >/tmp/apk.diff || true
cd /tmp
if python3 - "$REF" "/out/${APPID}_${VC}.apk" <<'EOF'
import sys, tempfile
from fdroidserver import common

common.read_config()
with tempfile.TemporaryDirectory() as tmp:
    sys.exit(common.verify_apks(sys.argv[1], sys.argv[2], tmp))
EOF
then
  echo "REPRODUCIBLE: the reference APK's signature verifies on the F-Droid" \
    "build ($(entries "$REF" | wc -l) entries, all identical)."
else
  echo "NOT REPRODUCIBLE: entries that differ from the reference APK:"
  sed -n 's/^[<>] [0-9a-f]* /  /p' /tmp/apk.diff | sort -u
  [ "$MODE" != rehearse ] || exit 1
fi
