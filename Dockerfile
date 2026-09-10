# =============================================================================
#  OWASP Juice Shop — DELIBERATELY VULNERABLE DEMO IMAGE
#  For Qualys code->image + runtime "package in use" demonstration ONLY.
#  Never expose, publish to an untrusted registry, or deploy to any reachable
#  host. It ships known-exploited, CVSS-10 components on purpose.
# =============================================================================

# ── Stage 1: build Juice Shop the way upstream does ──────────────────────────
FROM node:22 AS installer

COPY . /juice-shop
WORKDIR /juice-shop

# Pin npm >=12: node:22 ships npm 10.9.8, which crashes on the frontend's
# $-reference overrides with "Cannot read properties of null (reading 'edgesOut')".
RUN npm i -g npm@12.0.2
RUN npm i -g typescript ts-node
RUN npm install --omit=dev
RUN npm dedupe || true
RUN rm -rf frontend/node_modules

# ── Add deliberately-vulnerable npm packages into the app's node_modules ─────
# Installed alongside Juice Shop's real deps so the running node process can
# require() them -> they map into memory and appear as "in use" at runtime.
#   node-serialize@0.0.4  CVE-2017-5941   RCE via untrusted deserialization
#   ejs@2.5.7             CVE-2017-1000228 / CVE-2022-29078  RCE
#   jsonwebtoken@0.4.0    CVE-2015-9235   auth bypass (alg confusion)
#   lodash@4.17.4         CVE-2019-10744  prototype pollution (CVSS 9.1)
#   handlebars@4.0.5      CVE-2019-19919  prototype pollution -> RCE (CVSS 9.8)
#   marked@0.3.5          CVE-2017-1000427 / ReDoS
#   minimist@0.0.8        CVE-2020-7598   prototype pollution
#   st@0.2.4              CVE-2014-3744   path traversal
RUN npm install --no-save --omit=dev \
      node-serialize@0.0.4 \
      ejs@2.5.7 \
      jsonwebtoken@0.4.0 \
      lodash@4.17.4 \
      handlebars@4.0.5 \
      marked@0.3.5 \
      minimist@0.0.8 \
      st@0.2.4 \
      || true

# Wrapper that require()s the vulnerable packages and then boots Juice Shop
# IN THE SAME long-running process, so they stay mapped in memory for the
# entire lifetime the runtime sensor observes — not a short-lived side process.
RUN printf "%s\n" \
  "// Force the vulnerable deps to load into this long-running process." \
  "try { require('node-serialize'); } catch (e) {}" \
  "try { require('ejs'); } catch (e) {}" \
  "try { require('jsonwebtoken'); } catch (e) {}" \
  "try { require('lodash'); } catch (e) {}" \
  "try { require('handlebars'); } catch (e) {}" \
  "try { require('marked'); } catch (e) {}" \
  "try { require('minimist'); } catch (e) {}" \
  "try { require('st'); } catch (e) {}" \
  "console.log('[demo] vulnerable deps loaded into process ' + process.pid);" \
  "// Hand off to Juice Shop in this same process." \
  "require('/juice-shop/build/app.js');" \
  > /juice-shop/start-with-vulns.js

# ── Stage 2: runtime image (Debian base -> extra OS-package CVEs, stays runnable)
FROM node:22-bookworm

LABEL org.opencontainers.image.title="Juice Shop (deliberately vulnerable demo)" \
      org.opencontainers.image.description="Qualys code-to-cloud + runtime in-use demo. Do not deploy."

WORKDIR /juice-shop
COPY --from=installer /juice-shop .

# ── Java KEV / CVSS-10 jars: fingerprinted by the STATIC image scan ──────────
# No JVM in this image, so these are "installed" (scan) not "in use" (runtime).
# That split is expected — KEV/CVSS-10 coverage comes from the static scan.
#   log4j-core 2.14.1        CVE-2021-44228 Log4Shell        CVSS 10.0  KEV
#   struts2-core 2.3.31      CVE-2017-5638  OGNL RCE          CVSS 10.0  KEV
#   spring-beans 5.3.17      CVE-2022-22965 Spring4Shell      CVSS 9.8   KEV
#   commons-collections 3.2.1 CVE-2015-7501 deserialization   CVSS 9.8   KEV
#   commons-text 1.9         CVE-2022-42889 Text4Shell        CVSS 9.8   KEV
RUN mkdir -p /opt/vuln && cd /opt/vuln \
 && for url in \
    https://repo1.maven.org/maven2/org/apache/logging/log4j/log4j-core/2.14.1/log4j-core-2.14.1.jar \
    https://repo1.maven.org/maven2/org/apache/struts/struts2-core/2.3.31/struts2-core-2.3.31.jar \
    https://repo1.maven.org/maven2/org/springframework/spring-beans/5.3.17/spring-beans-5.3.17.jar \
    https://repo1.maven.org/maven2/commons-collections/commons-collections/3.2.1/commons-collections-3.2.1.jar \
    https://repo1.maven.org/maven2/org/apache/commons/commons-text/1.9/commons-text-1.9.jar \
 ; do wget -q "$url" || exit 1 ; done

EXPOSE 3000

# One long-running node process: vulnerable deps loaded + Juice Shop serving.
CMD ["node", "/juice-shop/start-with-vulns.js"]
