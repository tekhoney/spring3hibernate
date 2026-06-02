pipeline {
    agent any

    environment {
        REGISTRY = 'krishan9818'
        IMAGE_NAME = 'spring3hibernate'
        IMAGE_TAG = "${BUILD_NUMBER}"
        kubeConfig = '--kubeconfig=/var/lib/jenkins/.kube/config'
    }

    options {
        timeout(time: 1, unit: 'HOURS')
        ansiColor('xterm')
    }

    stages {
        // --- STAGE 1: BUILD & PACKAGE ---
        stage('Build & Package') {
            steps {
                echo 'Building Application using Maven...'
                sh 'mvn clean package -DskipTests'
            }
        }

        // --- STAGE 2: DOCKER BUILD & PUSH ---
        stage('Docker Build & Push') {
            steps {
                script {
                    docker.withRegistry('https://index.docker.io/v1/', 'docker-hub-creds') {
                        echo 'Building Docker Image...'
                        sh "docker build -t ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG} ."
                        
                        echo 'Pushing Docker Image to Registry...'
                        sh "docker push ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
                    }
                }
            }
        }

        // --- STAGE 3: DEPLOY TO DEV ---
        stage('Deploy to Dev') {
            steps {
                echo 'Deploying to Development Environment...'
                sh "kubectl ${kubeConfig} set image deployment/spring-app spring-app=${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG} -n dev"
            }
        }

        // --- STAGE 4: DEPLOY TO STAGING ---
        stage('Deploy to Staging') {
            steps {
                echo 'Deploying to Staging Environment...'
                sh "kubectl ${kubeConfig} set image deployment/spring-app spring-app=${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG} -n staging"
            }
        }

        // --- STAGE 5: PRODUCTION ENVIRONMENT (BLUE-GREEN) ---
        stage('Approve Production') {
            steps {
                input message: 'Approve Production Blue-Green Deployment?', ok: 'Approve'
            }
        }

        stage('Deploy to Production (Blue-Green)') {
            steps {
                milestone(30) 
                script {
                    // 1. Check active color
                    def activeColor = ""
                    try {
                        activeColor = sh(script: "kubectl ${kubeConfig} get svc spring-app-prod -n prod -o jsonpath='{.spec.selector.color}'", returnStdout: true).trim()
                    } catch (Exception e) {
                        echo "Service not found or no active color yet. Starting fresh."
                    }
                    
                    def targetColor = (activeColor == 'blue') ? 'green' : 'blue'
                    
                    echo "Current Active Environment: ${activeColor ? activeColor : 'None'}"
                    echo "Deploying to Target Environment: ${targetColor}"

                    // 2. Deploy to target color
                    sh """
                        kubectl ${kubeConfig} set image deployment/spring-app-${targetColor} spring-app=${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG} -n prod
                        kubectl ${kubeConfig} rollout status deployment/spring-app-${targetColor} -n prod
                    """

                    // 3. Health Check via Internal Curl (Bypassing Network Isolation)
                    try {
                        echo "Running Health Check inside the cluster via curl..."
                        
                        // Hum naye pod ke andar hi curl command chalakar status code check karenge
                        // Agar status code 200 aaya toh pass, nahi toh fail
                        def checkCommand = "kubectl ${kubeConfig} exec -n prod deployment/spring-app-${targetColor} -- curl -sL -o /dev/null -w '%{http_code}' http://localhost:8080/spring3hibernate"
                        
                        def statusCode = sh(script: checkCommand, returnStdout: true).trim()
                        echo "Health Check Response Code: ${statusCode}"
                        
                        if (statusCode == "200") {
                            echo "Health Check Passed!"
                            
                            // 4. Traffic Switch
                            echo "Switching live traffic to ${targetColor}..."
                            sh "kubectl ${kubeConfig} patch svc spring-app-prod -n prod -p '{\"spec\":{\"selector\":{\"color\":\"${targetColor}\"}}}'"
                            echo "Traffic successfully switched!"
                        } else {
                            error "Application responded with status code: ${statusCode}"
                        }
                        
                    } catch (Exception e) {
                        echo "Health Check Failed! Triggering Automatic Rollback..."
                        // 5. Automatic Rollback
                        sh "kubectl ${kubeConfig} rollout undo deployment/spring-app-${targetColor} -n prod"
                        error "Deployment failed due to health check failure. Rollback completed safely."
                    }
                }
            }
        }
    }

    post {
        always {
            cleanWs()
            echo 'Workspace cleaned successfully.'
        }
        success {
            echo 'Pipeline executed successfully! All stages passed.'
        }
        failure {
            echo 'Pipeline failed. Please check the logs.'
        }
    }
}
