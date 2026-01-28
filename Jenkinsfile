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
                sh 'docker build -t static-website .'
            }
        }

        stage('Run Website') {
            steps {
                sh '''
                docker stop website || true
                docker rm website || true
                docker run -d -p 8081:80 --name website static-website
                '''
            }
        }
    }
}
