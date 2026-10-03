// Jenkins pipeline: mirrors .github/workflows/ci.yml and runs inside a
// throwaway Docker container so every build is an isolated sandbox.
//
// Jenkins prerequisites:
//   - Docker Pipeline plugin + Docker available on the agent
//   - SSH credential (kind: "SSH Username with private key") with id
//     `sdk-deploy-key` -- the read-only deploy key for the private
//     daily_routine_sdk repo referenced in pubspec.yaml
pipeline {
    agent {
        docker {
            // Pin to the Flutter version you develop against.
            image 'ghcr.io/cirruslabs/flutter:stable'
            args '-e HOME=/tmp/home'
        }
    }

    options {
        timestamps()
        timeout(time: 30, unit: 'MINUTES')
        disableConcurrentBuilds(abortPrevious: true)
        buildDiscarder(logRotator(numToKeepStr: '20'))
    }

    environment {
        PUB_CACHE = "${WORKSPACE}/.pub-cache"
        CI = 'true'
    }

    stages {
        stage('Setup') {
            steps {
                sshagent(credentials: ['sdk-deploy-key']) {
                    sh '''
                        mkdir -p ~/.ssh && ssh-keyscan github.com >> ~/.ssh/known_hosts
                        # .env files are pubspec assets but gitignored; empty
                        # placeholders satisfy the asset check. No real secrets
                        # reach the sandbox.
                        touch .env .env.local
                        flutter --version
                        flutter pub get
                    '''
                }
            }
        }

        stage('Analyze') {
            steps {
                sh 'flutter analyze'
            }
        }

        stage('Format check') {
            steps {
                // Non-blocking, same as GitHub CI.
                catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') {
                    sh 'dart format --output=none --set-exit-if-changed .'
                }
            }
        }

        stage('Test') {
            steps {
                sh '''
                    if [ -d test ]; then
                        flutter test --machine > test-results.json || EXIT=$?
                        flutter test --coverage || true
                        exit ${EXIT:-0}
                    else
                        echo "No test/ directory, skipping."
                    fi
                '''
            }
            post {
                always {
                    archiveArtifacts artifacts: 'coverage/lcov.info, test-results.json',
                                     allowEmptyArchive: true
                }
            }
        }
    }

    post {
        cleanup {
            cleanWs()
        }
    }
}
