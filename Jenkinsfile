pipeline {
    agent any

    stages {
        stage('Clone Code') {
            steps {
                git branch: 'main',
                    url: 'https://github.com/ramya-harshinivs26/multi-cloud-devops.git'
            }
        }

        stage('Build Docker Image') {
            steps {
                bat 'docker build -t static-website .'
            }
        }

        stage('Run Website') {
            steps {
                bat '''
                docker stop website >nul 2>&1 || exit /b 0
                docker rm website >nul 2>&1 || exit /b 0
                docker run -d -p 8081:80 --name website static-website
                '''
            }
        }
    }
}
