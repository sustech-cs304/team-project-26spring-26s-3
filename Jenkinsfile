def windowsToolSetup() {
  return '''
if not "%DEVECO_HOME_OVERRIDE%"=="" set "DEVECO_HOME=%DEVECO_HOME_OVERRIDE%"
if "%DEVECO_HOME%"=="" (
  echo DEVECO_HOME is required. Configure it globally in Jenkins or set DEVECO_HOME_OVERRIDE for this build.
  exit /b 1
)

if not "%DEVECO_SDK_HOME_OVERRIDE%"=="" set "DEVECO_SDK_HOME=%DEVECO_SDK_HOME_OVERRIDE%"
if "%DEVECO_SDK_HOME%"=="" set "DEVECO_SDK_HOME=%DEVECO_HOME%\\sdk"

if not "%JAVA_HOME_OVERRIDE%"=="" set "JAVA_HOME=%JAVA_HOME_OVERRIDE%"

set "NODE_HOME=%DEVECO_HOME%\\tools\\node"
set "HVIGOR_BIN=%DEVECO_HOME%\\tools\\hvigor\\bin\\hvigorw.bat"
set "OHPM_BIN=%DEVECO_HOME%\\tools\\ohpm\\bin\\ohpm.bat"
set "NODE_BIN=%NODE_HOME%\\node.exe"
set "NPM_BIN=%NODE_HOME%\\npm.cmd"
set "HDC_BIN=%DEVECO_SDK_HOME%\\default\\openharmony\\toolchains\\hdc.exe"

set "NPM_CONFIG_CACHE=%WORKSPACE%\\.ci-cache\\npm"
set "NPM_CONFIG_PREFIX=%WORKSPACE%\\.ci-cache\\npm-global"
set "PNPM_HOME=%WORKSPACE%\\.ci-cache\\pnpm"
if not exist "%NPM_CONFIG_CACHE%" mkdir "%NPM_CONFIG_CACHE%"
if not exist "%NPM_CONFIG_PREFIX%" mkdir "%NPM_CONFIG_PREFIX%"
if not exist "%PNPM_HOME%" mkdir "%PNPM_HOME%"

if not "%JAVA_HOME%"=="" (
  if not exist "%JAVA_HOME%\\bin\\java.exe" (
    echo JAVA_HOME points to an invalid JDK: %JAVA_HOME%
    exit /b 1
  )
  set "PATH=%JAVA_HOME%\\bin;%PATH%"
)
set "PATH=%NODE_HOME%;%DEVECO_HOME%\\tools\\ohpm\\bin;%DEVECO_HOME%\\tools\\hvigor\\bin;%NPM_CONFIG_PREFIX%;%PNPM_HOME%;%PATH%"
'''
}

def repoWindowsPrefix() {
  return '''
if "%REPO_DIR%"=="" (
  set "REPO_DIR=%WORKSPACE%"
)
if "%REPO_DIR%"=="" (
  echo REPO_DIR is required because WORKSPACE is empty. Set it to the repository root on this Jenkins node.
  exit /b 1
)
cd /d "%REPO_DIR%" || exit /b 1
'''
}

def unixToolSetup() {
  return '''
set -eu

if [ -n "${DEVECO_HOME_OVERRIDE:-}" ]; then
  export DEVECO_HOME="$DEVECO_HOME_OVERRIDE"
fi
if [ -z "${DEVECO_HOME:-}" ]; then
  echo "DEVECO_HOME is required. Configure it globally in Jenkins or set DEVECO_HOME_OVERRIDE for this build."
  exit 1
fi

if [ -n "${JAVA_HOME_OVERRIDE:-}" ]; then
  export JAVA_HOME="$JAVA_HOME_OVERRIDE"
fi

if [ -n "${DEVECO_SDK_HOME_OVERRIDE:-}" ]; then
  export DEVECO_SDK_HOME="$DEVECO_SDK_HOME_OVERRIDE"
else
  export DEVECO_SDK_HOME="${DEVECO_SDK_HOME:-$DEVECO_HOME/sdk}"
fi

export NODE_HOME="$DEVECO_HOME/tools/node"
export HVIGOR_BIN="$DEVECO_HOME/tools/hvigor/bin/hvigorw"
export OHPM_BIN="$DEVECO_HOME/tools/ohpm/bin/ohpm"
export NODE_BIN="$NODE_HOME/bin/node"
export NPM_BIN="$NODE_HOME/bin/npm"
export HDC_BIN="$DEVECO_SDK_HOME/default/openharmony/toolchains/hdc"

export NPM_CONFIG_CACHE="$WORKSPACE/.ci-cache/npm"
export NPM_CONFIG_PREFIX="$WORKSPACE/.ci-cache/npm-global"
export PNPM_HOME="$WORKSPACE/.ci-cache/pnpm"
mkdir -p "$NPM_CONFIG_CACHE" "$NPM_CONFIG_PREFIX" "$PNPM_HOME"

if [ -n "${JAVA_HOME:-}" ]; then
  test -x "$JAVA_HOME/bin/java"
  export PATH="$JAVA_HOME/bin:$PATH"
fi
export PATH="$NODE_HOME/bin:$DEVECO_HOME/tools/ohpm/bin:$DEVECO_HOME/tools/hvigor/bin:$NPM_CONFIG_PREFIX/bin:$PNPM_HOME:$PATH"
'''
}

def repoUnixPrefix() {
  return '''
if [ -z "${REPO_DIR:-}" ]; then
  export REPO_DIR="$WORKSPACE"
fi
if [ -z "${REPO_DIR:-}" ]; then
  echo "REPO_DIR is required because WORKSPACE is empty. Set it to the repository root on this Jenkins node."
  exit 1
fi
cd "$REPO_DIR"
'''
}

def runCi(String windowsBody, String unixBody) {
  if (isUnix()) {
    sh(label: 'run shell step', script: """
export DEVECO_HOME_OVERRIDE='${params.DEVECO_HOME_OVERRIDE ?: ''}'
export DEVECO_SDK_HOME_OVERRIDE='${params.DEVECO_SDK_HOME_OVERRIDE ?: ''}'
export JAVA_HOME_OVERRIDE='${params.JAVA_HOME_OVERRIDE ?: ''}'
export REPO_DIR_OVERRIDE='${params.REPO_DIR ?: ''}'
if [ -n "\$REPO_DIR_OVERRIDE" ]; then
  export REPO_DIR="\$REPO_DIR_OVERRIDE"
fi
${unixToolSetup()}
${repoUnixPrefix()}
${unixBody}
""")
  } else {
    bat(label: 'run batch step', script: """@echo on
set "DEVECO_HOME_OVERRIDE=${params.DEVECO_HOME_OVERRIDE ?: ''}"
set "DEVECO_SDK_HOME_OVERRIDE=${params.DEVECO_SDK_HOME_OVERRIDE ?: ''}"
set "JAVA_HOME_OVERRIDE=${params.JAVA_HOME_OVERRIDE ?: ''}"
set "REPO_DIR_OVERRIDE=${params.REPO_DIR ?: ''}"
if not "%REPO_DIR_OVERRIDE%"=="" set "REPO_DIR=%REPO_DIR_OVERRIDE%"
${windowsToolSetup()}
${repoWindowsPrefix()}
${windowsBody}""")
  }
}

def runHvigorBuild() {
  if (isUnix()) {
    return sh(
      label: 'build unsigned HAP',
      returnStatus: true,
      script: """
export DEVECO_HOME_OVERRIDE='${params.DEVECO_HOME_OVERRIDE ?: ''}'
export DEVECO_SDK_HOME_OVERRIDE='${params.DEVECO_SDK_HOME_OVERRIDE ?: ''}'
export JAVA_HOME_OVERRIDE='${params.JAVA_HOME_OVERRIDE ?: ''}'
export REPO_DIR_OVERRIDE='${params.REPO_DIR ?: ''}'
if [ -n "\$REPO_DIR_OVERRIDE" ]; then
  export REPO_DIR="\$REPO_DIR_OVERRIDE"
fi
${unixToolSetup()}
${repoUnixPrefix()}
"\$HVIGOR_BIN" clean assembleApp --no-daemon --no-incremental --no-type-check
"""
    )
  }

  return bat(
    label: 'build unsigned HAP',
    returnStatus: true,
    script: """@echo on
set "DEVECO_HOME_OVERRIDE=${params.DEVECO_HOME_OVERRIDE ?: ''}"
set "DEVECO_SDK_HOME_OVERRIDE=${params.DEVECO_SDK_HOME_OVERRIDE ?: ''}"
set "JAVA_HOME_OVERRIDE=${params.JAVA_HOME_OVERRIDE ?: ''}"
set "REPO_DIR_OVERRIDE=${params.REPO_DIR ?: ''}"
if not "%REPO_DIR_OVERRIDE%"=="" set "REPO_DIR=%REPO_DIR_OVERRIDE%"
${windowsToolSetup()}
${repoWindowsPrefix()}
call "%HVIGOR_BIN%" clean assembleApp --no-daemon --no-incremental --no-type-check"""
  )
}

pipeline {
  agent any

  options {
    timestamps()
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '20', artifactNumToKeepStr: '10'))
  }

  parameters {
    string(name: 'REPO_DIR', defaultValue: '', description: 'Optional repository root on this Jenkins node. Leave empty when Jenkins checks out this repo into WORKSPACE.')
    string(name: 'DEVECO_HOME_OVERRIDE', defaultValue: '', description: 'Optional DevEco Studio home for this Jenkins node. Prefer a Jenkins global env var named DEVECO_HOME.')
    string(name: 'DEVECO_SDK_HOME_OVERRIDE', defaultValue: '', description: 'Optional HarmonyOS SDK home. Defaults to DEVECO_HOME/sdk.')
    string(name: 'JAVA_HOME_OVERRIDE', defaultValue: '', description: 'Optional JDK home for this Jenkins node. Prefer a Jenkins global env var named JAVA_HOME.')
    booleanParam(name: 'ALLOW_UNSIGNED_HAP', defaultValue: true, description: 'Allow signing failure when an unsigned HAP is still produced. Keep true until Jenkins signing credentials are configured.')
    booleanParam(name: 'RUN_DEVICE_SMOKE', defaultValue: false, description: 'Run a connected-device hdc smoke check. Enable only on nodes with a device or emulator attached.')
    booleanParam(name: 'RUN_HARMONYOS_DEVICE_TESTS', defaultValue: false, description: 'Run official HarmonyOS ohosTest/Hypium tests on a connected device or emulator.')
    booleanParam(name: 'COLLECT_HARMONYOS_COVERAGE', defaultValue: true, description: 'Run hvigor collectCoverage after HarmonyOS device tests.')
  }

  triggers {
    pollSCM('H/5 * * * *')
  }

  stages {
    stage('Clean Reports') {
      steps {
        script {
          runCi(
            '''
if exist reports rmdir /s /q reports
if exist .ci-cache\\tmp rmdir /s /q .ci-cache\\tmp
''',
            '''
rm -rf reports .ci-cache/tmp
'''
          )
        }
      }
    }

    stage('Environment') {
      steps {
        script {
          runCi(
            '''
if not exist "%HVIGOR_BIN%" exit /b 1
if not exist "%OHPM_BIN%" exit /b 1
if not exist "%NODE_BIN%" exit /b 1
if not exist "%NPM_BIN%" exit /b 1
if not exist "%DEVECO_SDK_HOME%\\default\\openharmony" exit /b 1

call "%OHPM_BIN%" --version
call "%HVIGOR_BIN%" --version
"%NODE_BIN%" --version
"%NPM_BIN%" --version
where java
java -version
''',
            '''
test -x "$HVIGOR_BIN"
test -x "$OHPM_BIN"
test -x "$NODE_BIN"
test -x "$NPM_BIN"
test -d "$DEVECO_SDK_HOME/default/openharmony"

"$OHPM_BIN" --version
"$HVIGOR_BIN" --version
"$NODE_BIN" --version
"$NPM_BIN" --version
command -v java
java -version
'''
          )
        }
      }
    }

    stage('Static Project Checks') {
      steps {
        script {
          runCi(
            '''
if not exist build-profile.json5 exit /b 1
if not exist hvigorfile.ts exit /b 1
if not exist entry\\src\\main\\module.json5 exit /b 1
if not exist entry\\src\\ohosTest\\module.json5 exit /b 1
if not exist Jenkinsfile exit /b 1
if not exist package-lock.json exit /b 1
if not exist tsconfig.ci.json exit /b 1
if not exist oh-package-lock.json5 exit /b 1
''',
            '''
test -f build-profile.json5
test -f hvigorfile.ts
test -f entry/src/main/module.json5
test -f entry/src/ohosTest/module.json5
test -f Jenkinsfile
test -f package-lock.json
test -f tsconfig.ci.json
test -f oh-package-lock.json5
'''
          )
        }
      }
    }

    stage('Install Node Test Dependencies') {
      steps {
        script {
          runCi(
            'call "%NPM_BIN%" ci --prefer-offline --no-audit --fund=false',
            '"$NPM_BIN" ci --prefer-offline --no-audit --fund=false'
          )
        }
      }
    }

    stage('TypeScript Typecheck') {
      steps {
        script {
          runCi(
            'call "%NPM_BIN%" run test:typecheck',
            '"$NPM_BIN" run test:typecheck'
          )
        }
      }
    }

    stage('Quality Gate') {
      steps {
        script {
          runCi(
            'call "%NPM_BIN%" run test:quality',
            '"$NPM_BIN" run test:quality'
          )
        }
      }
    }

    stage('Smoke Tests') {
      steps {
        script {
          runCi(
            'call "%NPM_BIN%" run test:smoke',
            '"$NPM_BIN" run test:smoke'
          )
        }
      }
    }

    stage('HarmonyOS Test Config Check') {
      steps {
        script {
          runCi(
            'call "%NPM_BIN%" run test:ohos',
            '"$NPM_BIN" run test:ohos'
          )
        }
      }
    }

    stage('Vitest Coverage') {
      steps {
        script {
          runCi(
            'call "%NPM_BIN%" run test:coverage',
            '"$NPM_BIN" run test:coverage'
          )
        }
      }
    }

    stage('Install OHPM Dependencies') {
      steps {
        script {
          runCi(
            '''
call "%NODE_BIN%" tests\\ci-ohpm-deps.mjs
if %ERRORLEVEL% EQU 0 (
  call "%OHPM_BIN%" install --all
) else (
  echo No OHPM dependencies declared; skipping ohpm install.
)
''',
            '''
if "$NODE_BIN" tests/ci-ohpm-deps.mjs; then
  "$OHPM_BIN" install --all
else
  echo "No OHPM dependencies declared; skipping ohpm install."
fi
'''
          )
        }
      }
    }

    stage('Build Unsigned HAP') {
      steps {
        script {
          int status = runHvigorBuild()
          if (status != 0 && !params.ALLOW_UNSIGNED_HAP) {
            error("Hvigor build failed with exit code ${status}.")
          }
          if (status != 0) {
            echo "Hvigor exited with ${status}; continuing because ALLOW_UNSIGNED_HAP is true. Package Check must still find an unsigned HAP."
          }
        }
      }
    }

    stage('Package Check') {
      steps {
        script {
          runCi(
            'call "%NPM_BIN%" run test:package',
            '"$NPM_BIN" run test:package'
          )
        }
      }
    }

    stage('Device Smoke') {
      when {
        expression { return params.RUN_DEVICE_SMOKE || params.RUN_HARMONYOS_DEVICE_TESTS }
      }
      steps {
        script {
          runCi(
            '''
if not exist "%HDC_BIN%" exit /b 1
set "HDC_TARGET="
for /f "usebackq tokens=*" %%i in (`"%HDC_BIN%" list targets`) do (
  if not "%%i"=="" if not "%%i"=="[Empty]" set "HDC_TARGET=%%i"
)
if "%HDC_TARGET%"=="" exit /b 1
echo Connected hdc target: %HDC_TARGET%
''',
            '''
test -x "$HDC_BIN"
target="$("$HDC_BIN" list targets | sed '/^[[:space:]]*$/d;/^\\[Empty\\]/d' | head -n 1)"
test -n "$target"
echo "Connected hdc target: $target"
'''
          )
        }
      }
    }

    stage('HarmonyOS Device Tests') {
      when {
        expression { return params.RUN_HARMONYOS_DEVICE_TESTS }
      }
      steps {
        script {
          runCi(
            'call "%HVIGOR_BIN%" onDeviceTest --no-daemon --no-incremental --no-type-check',
            '"$HVIGOR_BIN" onDeviceTest --no-daemon --no-incremental --no-type-check'
          )
        }
      }
    }

    stage('HarmonyOS Runtime Coverage') {
      when {
        expression { return params.RUN_HARMONYOS_DEVICE_TESTS && params.COLLECT_HARMONYOS_COVERAGE }
      }
      steps {
        script {
          runCi(
            'call "%HVIGOR_BIN%" collectCoverage --no-daemon --no-type-check',
            '"$HVIGOR_BIN" collectCoverage --no-daemon --no-type-check'
          )
        }
      }
    }
  }

  post {
    always {
      junit allowEmptyResults: true, testResults: 'reports/tests/*.xml'
      archiveArtifacts artifacts: 'reports/tests/*.xml,reports/coverage/**/*,build/outputs/**/*.app,build/outputs/**/*.zip,entry/build/**/outputs/**/*.hap,entry/build/**/*coverage*/**,.hvigor/outputs/build-logs/*.log', fingerprint: true, allowEmptyArchive: true
    }
  }
}
