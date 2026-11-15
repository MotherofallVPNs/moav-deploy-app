#!/usr/bin/env bash
# Checks docs/fdroid/<appid>.yml the way fdroiddata's GitLab pipeline does,
# inside the F-Droid buildserver image. See docs/DISTRIBUTION.md (F-Droid).
#
#   scripts/fdroid-validate.sh lint    lint, rewritemeta, checkupdates
#   scripts/fdroid-validate.sh build   full `fdroid build` of the latest entry
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
  exec docker run --rm --platform linux/amd64 \
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
  fdroid checkupdates --auto "$APPID"
  if ! git diff --exit-code -- "metadata/$APPID.yml"; then
    echo "FAIL: rewritemeta or checkupdates changed the recipe (diff above)."
    exit 1
  fi
  echo "OK: lint, rewritemeta and checkupdates are clean for $APPID:$VC."
  exit 0
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

# Informational: distance from the signed GitHub Release APK (reproducibility).
VN=$(sed -n 's/^CurrentVersion: //p' "$DATA/metadata/$APPID.yml")
RELEASE_APK=https://github.com/MotherofallVPNs/moav-deploy-app/releases/download/v$VN/app-release.apk
entries() { unzip -v "$1" | awk '$7 ~ /^[0-9a-f]{8}$/ {print $7, $8}' | sort -k2; }
if curl -fsSL -o /tmp/release.apk "$RELEASE_APK"; then
  if diff <(entries /tmp/release.apk) <(entries "/out/${APPID}_${VC}.apk") >/tmp/apk.diff; then
    echo "REPRODUCIBLE: every entry matches the v$VN release APK."
  else
    echo "NOT REPRODUCIBLE YET: entries that differ from the v$VN release APK:"
    sed -n 's/^> [0-9a-f]* /  /p' /tmp/apk.diff
  fi
else
  echo "No release APK at $RELEASE_APK; skipped the comparison."
fi
