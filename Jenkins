pipeline {
    agent any

    environment {
        REGISTRY = "your-dockerhub-username" // Apna Docker Hub username yahan likhein
        IMAGE_NAME = "spring3hibernate"
        IMAGE_TAG = "${BUILD_NUMBER}"
        KUBECONFIG_CREDENTIAL_ID = 'k8s-kubeconfig'
    }

    options {
        timeout(time: 1, unit: 'HOURS')
        ansiColor('xterm')
    }

    stages {
        // --- STAGE 1: BUILD & PUSH ---
        stage('Build & Package') {
            steps {
                echo 'Building Application...'
                // Spring 3 application ko build karne ke liye maven ka use
                sh './mvnw clean package -DskipTests'
            }
        }

        stage('Docker Build & Push') {
            steps {
                script {
                    docker.withRegistry('', 'docker-hub-creds') {
                        def customImage = docker.build("${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}")
                        customImage.push()
                        customImage.push("latest")
                    }
                }
            }
        }

        // --- STAGE 2: DEV ENVIRONMENT (AUTOMATIC) ---
        stage('Deploy to Dev') {
            options { milestone(10) } // Concurrency control ke liye
            steps {
                withKubeConfig([credentialsId: KUBECONFIG_CREDENTIAL_ID]) {
                    echo 'Deploying to Development Environment...'
                    sh """
                        kubectl set image deployment/spring-app spring-app=${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG} -n dev --record
                        kubectl rollout status deployment/spring-app -n dev
                    """
                }
            }
        }

        // --- STAGE 3: STAGING ENVIRONMENT (MANUAL APPROVAL) ---
        stage('Approve Staging') {
            steps {
                input message: 'Do you want to deploy to Staging?', ok: 'Deploy'
            }
        }

        stage('Deploy to Staging') {
            options { milestone(20) }
            steps {
                withKubeConfig([credentialsId: KUBECONFIG_CREDENTIAL_ID]) {
                    echo 'Deploying to Staging Environment...'
                    sh """
                        kubectl set image deployment/spring-app spring-app=${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG} -n staging --record
                        kubectl rollout status deployment/spring-app -n staging
                    """
                }
            }
        }

        // --- STAGE 4: PRODUCTION ENVIRONMENT (BLUE-GREEN) ---
        stage('Approve Production') {
            steps {
                input message: 'Approve Production Blue-Green Deployment?', ok: 'Approve'
            }
        }

        stage('Deploy to Production (Blue-Green)') {
            options { milestone(30) }
            steps {
                withKubeConfig([credentialsId: KUBECONFIG_CREDENTIAL_ID]) {
                    script {
                        // 1. Identify current active color (Blue or Green) via Service selector
                        def activeColor = sh(script: "kubectl get svc spring-app-prod -n prod -o jsonpath='{.spec.selector.color}'", returnStdout: true).trim()
                        def targetColor = (activeColor == 'blue') ? 'green' : 'blue'
                        
                        echo "Current Active Environment: ${activeColor}"
                        echo "Deploying to Target Environment: ${targetColor}"

                        // 2. Update target environment deployment
                        sh """
                            kubectl set image deployment/spring-app-${targetColor} spring-app=${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG} -n prod --record
                            kubectl rollout status deployment/spring-app-${targetColor} -n prod
                        """

                        // 3. Health Check Verification
                        // Target environment ki internal service IP/DNS ya nodeport par check karein
                        def targetSvcUrl = "http://spring-app-${targetColor}.prod.svc.cluster.local:8080/spring3hibernate" 
                        echo "Running Health Check on ${targetSvcUrl}..."
                        
                        try {
                            // HTTP request plugin ka use karke status check
                            def response = httpRequest url: targetSvcUrl, validResponseCodes: '200'
                            echo "Health Check Passed!"
                            
                            // 4. Traffic Switch (Switch active service to new color)
                            echo "Switching traffic to ${targetColor}..."
                            sh "kubectl patch svc spring-app-prod -n prod -p '{\"spec\":{\"selector\":{\"color\":\"${targetColor}\"}}}'"
                            
                        } catch (Exception e) {
                            echo "Health Check Failed! Triggering Automatic Rollback..."
                            // Rollback: Target deployment ko purani image par wapas le jao (ya scale down kar do)
                            sh "kubectl rollout undo deployment/spring-app-${targetColor} -n prod"
                            error "Deployment failed due to health check failure."
                        }
                    }
                }
            }
        }
    }

    post {
        always {
            cleanWs()
        }
        success {
            echo 'Pipeline successfully completed!'
        }
        failure {
            echo 'Pipeline failed. Check logs for details.'
        }
    }
}
