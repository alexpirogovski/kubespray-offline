@Library('pipelinex@development') _

def upload_to_s3_generic(aws_auth_id, bucket, bucket_region, source, dest, follow_sym_links = false) {
    withEnv(["AWS_DEFAULT_REGION=${bucket_region}"]) {
        withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: aws_auth_id]]) {
            common.shell(['virtualenv', '-p', 'python3', 'venv'])
            common.shell(['source', 'venv/bin/activate'])
            common.shell(['python', '-V'])
            common.shell(['python', '-m', 'pip', 'install', 'awscli'])
            common.shell(['aws', 'configure', 'set', 'default.s3.max_concurrent_requests', '50'])

            def is_dir = sh(script: "test -d ${source}", returnStatus: true)
            def s3_cmd = is_dir == 0 ? 'sync' : 'cp'
            def symlinks_follow_arg = follow_sym_links ? '--follow-symlinks' : '--no-follow-symlinks'
            def cmd = ['aws', 's3', s3_cmd, '--no-progress', symlinks_follow_arg, '--storage-class', 'REDUCED_REDUNDANCY', source, "s3://${bucket}/${dest}"]

            common.shell(cmd)
        }
    }
}

def upload_to_s3(bucket, bucket_region, source, dest, follow_sym_links = false) {
    def amazon_auth_id = '42a3c90a-5640-4894-87d0-e9cd6bb000cb'
    upload_to_s3_generic(amazon_auth_id, bucket, bucket_region, source, dest, follow_sym_links)
}

def config = common.get_config()

def props = [
        buildDiscarder(logRotator(artifactDaysToKeepStr: '', artifactNumToKeepStr: '', daysToKeepStr: '30', numToKeepStr: '1000'))
    ]

if (config.cron.get(env.BRANCH_NAME)) {
    props.add(pipelineTriggers([cron(config.cron.get(env.BRANCH_NAME))]))
}

properties(props)

common.main {
    nodes.builder('tel-ad') {
        timestamps {

            stage('checkout') {
                deleteDir()
                final scm_vars = checkout scm

                env.kubespray_hash = scm_vars.GIT_COMMIT
                currentBuild.description = "branch ${env.BRANCH_NAME}, ${env.kubespray_hash}"
            }

            stage('build') {
                dir('./') {
                    def docker_img_name = "devops/kubespray_builder:${env.kubespray_hash}"

                    common.shell(['docker', 'build', '-f', 'Dockerfile_centos7', '-t', docker_img_name, '.'])

                    try {
                            sh "docker run -v \$(pwd)/outputs:/outputs -v /var/run/docker.sock:/var/run/docker.sock ${docker_img_name} || exit 1"
                    } finally {
                        // let's save time and bandwidth
                        common.shell(['docker', 'rm', '-f', docker_img_name])
                        common.shell(['docker', 'rmi', '-f', docker_img_name])
                    }
                }
            }

            stage('upload assets') {
                parallel(
                    'upload_to_nas': {
                        def build_by_hash_dir = "/mnt/nas/build_by_hash/kubespray"
                        def nas_dir = "${build_by_hash_dir}/${env.kubespray_hash}/pkg/kubespray"
                        sh("mkdir -p ${nas_dir}")
                        sh("cp -r outputs ${nas_dir}/")
                    },
                    'upload_to_s3': {
                        def bucket = 'iguazio-versions'
                        def bucket_region = 'us-east-1'
                        upload_to_s3(bucket, bucket_region, 'outputs', "build_by_hash/kubespray/${env.kubespray_hash}/pkg/kubespray/outputs")
                    }
                )
            }
        }
    }
}
