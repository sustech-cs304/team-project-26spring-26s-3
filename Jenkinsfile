pipeline {
  agent any

  options {
    timestamps()
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '20', artifactNumToKeepStr: '10'))
  }

  triggers {
    pollSCM('H/5 * * * *')
  }

  environment {
    DEVECO_HOME = '/Applications/DevEco-Studio.app/Contents'
    DEVECO_SDK_HOME = "${DEVECO_HOME}/sdk"
    HVIGOR_BIN = "${DEVECO_HOME}/tools/hvigor/bin/hvigorw"
    OHPM_BIN = "${DEVECO_HOME}/tools/ohpm/bin/ohpm"
    PATH = "${DEVECO_HOME}/tools/node/bin:${DEVECO_HOME}/tools/ohpm/bin:${DEVECO_HOME}/tools/hvigor/bin:${env.PATH}"
  }

  stages {
    stage('Environment') {
      steps {
        sh '''
          set -eu
          test -x "$HVIGOR_BIN"
          test -x "$OHPM_BIN"
          test -d "$DEVECO_SDK_HOME/default/openharmony"

          "$OHPM_BIN" --version
          "$HVIGOR_BIN" --version
        '''
      }
    }

    stage('Static Checks') {
      steps {
        sh '''
          set -eu
          test -f build-profile.json5
          test -f hvigorfile.ts
          test -f entry/src/main/module.json5

          echo "ArkTS/ETS source files:"
          find entry/src/main/ets -type f \\( -name '*.ets' -o -name '*.ts' \\) | wc -l
        '''
      }
    }

    stage('Run Tests') {
      steps {
        sh '''
          set -eu
          node tests/ci-smoke.test.mjs
        '''
      }
    }

    stage('Install Dependencies') {
      steps {
        sh '''
          set -eu
          if grep -q '"dependencies" *: *{}' oh-package.json5 && grep -q '"dependencies" *: *{}' entry/oh-package.json5; then
            echo "No OHPM dependencies declared; skipping ohpm install."
          else
            "$OHPM_BIN" install --all
          fi
        '''
      }
    }

    stage('Build') {
      steps {
        sh '''
          set -eu
          "$HVIGOR_BIN" clean assembleApp --no-daemon --no-incremental --no-type-check
        '''
      }
    }

    stage('Package Check') {
      steps {
        sh '''
          set -eu
          test -f build/outputs/default/team-project-26spring-26s-3-default-signed.app
          test -f entry/build/default/outputs/default/entry-default-signed.hap

          ls -lh build/outputs/default/*.app entry/build/default/outputs/default/*.hap
        '''
      }
    }
  }

  post {
    always {
      archiveArtifacts artifacts: 'reports/tests/*.xml,build/outputs/**/*.app,build/outputs/**/*.zip,entry/build/**/outputs/**/*.hap,.hvigor/outputs/build-logs/*.log', fingerprint: true, allowEmptyArchive: true
    }
  }
}
