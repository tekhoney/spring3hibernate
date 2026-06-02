pipeline {
    agent any

    environment {
        REGISTRY = "your-dockerhub-username" // ⚠️ Yahan apna Docker Hub username zaroor likhein
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
                echo 'Building Application using Maven...'
                sh './mvn clean package -DskipTests'
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
            steps {
                milestone(10) // ✅ Syntax fix: Steps ke andar milestone
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
            steps {
                milestone(20) // ✅ Syntax fix: Steps ke andar milestone
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
            steps {
                milestone(30) // ✅ Syntax fix: Steps ke andar milestone
                withKubeConfig([credentialsId: KUBECONFIG_CREDENTIAL_ID]) {
                    script {
                        // 1. Pata karein ki abhi kaunsa color active hai (Blue ya Green) via Service selector
                        def activeColor = sh(script: "kubectl get svc spring-app-prod -n prod -o jsonpath='{.spec.selector.color}'", returnStdout: true).trim()
                        def targetColor = (activeColor == 'blue') ? 'green' : 'blue'
                        
                        echo "Current Active Environment: ${activeColor}"
                        echo "Deploying to Target Environment: ${targetColor}"

                        // 2. Naye code ko target environment (idle color) par deploy karein
                        sh """
                            kubectl set image deployment/spring-app-${targetColor} spring-app=${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG} -n prod --record
                            kubectl rollout status deployment/spring-app-${targetColor} -n prod
                        """

                        // 3. Health Check Verification (httpRequest step)
                        // Note: Minikube mein cluster IP local hoti hai, isliye targetSvcUrl bilkul sahi hai
                        def targetSvcUrl = "http://spring-app-${targetColor}.prod.svc.cluster.local:8080/spring3hibernate" 
                        echo "Running Health Check on: ${targetSvcUrl}"
                        
                        try {
                            // HTTP request plugin ka use karke response validation
                            def response = httpRequest url: targetSvcUrl, validResponseCodes: '200'
                            echo "Health Check Passed!"
                            
                            // 4. Traffic Switch (Agar health check pass hua toh service ko new color par switch karein)
                            echo "Switching traffic to ${targetColor}..."
                            sh "kubectl patch svc spring-app-prod -n prod -p '{\"spec\":{\"selector\":{\"color\":\"${targetColor}\"}}}'"
                            
                        } catch (Exception e) {
                            echo "Health Check Failed! Triggering Automatic Rollback..."
                            // 5. Automatic Rollback on failure
                            sh "kubectl rollout undo deployment/spring-app-${targetColor} -n prod"
                            error "Deployment failed due to health check failure. Rollback completed."
                        }
                    }
                }
            }
        }
    }

    post {
        always {
            cleanWs() // Workspace clean karne ke liye
        }
        success {
            echo 'Pipeline successfully completed!'
        }
        failure {
            echo 'Pipeline failed. Please check the logs.'
        }
    }
}
