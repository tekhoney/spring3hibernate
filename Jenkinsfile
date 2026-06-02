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
                    // Yahan aapki exact screenshot wali ID 'docker-hub-creds' use kar li hai
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

                    // 3. Health Check via Pod IP (Bypassing Internal Cluster DNS)
                    try {
                        echo "Fetching Target Pod IP for Health Check..."
                        def podIp = sh(script: "kubectl ${kubeConfig} get pods -l color=${targetColor} -n prod -o jsonpath='{.items[0].status.podIP}'", returnStdout: true).trim()
                        
                        if (!podIp) {
                            error "Could not fetch Pod IP for health check."
                        }

                        def targetSvcUrl = "http://${podIp}:8080/spring3hibernate" 
                        echo "Running Health Check on: ${targetSvcUrl}"
                        
                        def response = httpRequest url: targetSvcUrl, validResponseCodes: '200'
                        echo "Health Check Passed!"
                        
                        // 4. Traffic Switch
                        echo "Switching live traffic to ${targetColor}..."
                        sh "kubectl ${kubeConfig} patch svc spring-app-prod -n prod -p '{\"spec\":{\"selector\":{\"color\":\"${targetColor}\"}}}'"
                        echo "Traffic successfully switched!"
                        
                    } catch (Exception e) {
                        echo "Health Check Failed! Triggering Automatic Rollback..."
                        // 5. Automatic Rollback
                        sh "kubectl ${kubeConfig} rollout undo deployment/spring-app-${targetColor} -n prod"
                        error "Deployment failed due to health check failure. Rollback completed safely."
                    }
                }
            }
        }
