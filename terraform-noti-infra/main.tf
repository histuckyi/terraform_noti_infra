# aws를 공급자로 사용하여 해당 리전에 인프라를 배포함
provider "aws" {
  region = "ap-northeast-2"
  profile = "terraform" # ~/.aws/credentials에 저장된 terraform의 프로파일 정보를 사용
}


# aws에서는 기본적으로 EC2 인스턴스에 들어오거나 나가는 트래픽을 허용하지 않으므로
# EC2가 8080 포트에서 트래픽을 수신하도록 하려면 보안 그룹을 생성해야 함
resource "aws_security_group" "instance" {
  name = "terraform-example-instance"
  ingress {
    from_port = var.server_port
    to_port   = var.server_port
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # 어디에서든 들어오는 모든 요청 허용, IP 주소 범위 지정
  }
}

resource "aws_instance" "example" {
  ami           = "ami-0272f9d2f3adaeea1" # 사용할 AMI ID
  instance_type = "t3.medium"             # 인스턴스 유형
  vpc_security_group_ids = [aws_security_group.instance.id]
  user_data = <<-EOF
              #!/bin/bash
              echo "Hello, World" > index.html
              nohup busybox httpd -f -p ${var.server_port} &
              EOF
  tags = {
    Name = "terraform-example"
  }
}

variable "server_port" {
  description = "The port the server will use for hTTP requests"
  type = number
  default = 8080
}

# 출력 변수의 이름
output "public_ip" {
  value = aws_instance.example.public_ip
  description = "The public IP address of the web server"
}