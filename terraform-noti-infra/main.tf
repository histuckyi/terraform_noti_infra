# aws를 공급자로 사용하여 해당 리전에 인프라를 배포함
provider "aws" {
  region = "ap-northeast-2"
  profile = "terraform" # ~/.aws/credentials에 저장된 terraform의 프로파일 정보를 사용
}


resource "aws_launch_configuration" "example" {
  image_id      = "ami-0272f9d2f3adaeea1" # 사용할 AMI ID
  instance_type = "t3.medium"             # 인스턴스 유형
  security_groups = [aws_security_group.instance.id]
  user_data = <<-EOF
              #!/bin/bash
              echo "Hello, World" > index.html
              nohup busybox httpd -f -p ${var.server_port} &
              EOF
  lifecycle {
    create_before_destroy = true
  }
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


resource "aws_lb_listener_rule" "asg" {
  listener_arn = aws_lb_listener.http.arn
  priority = 100

  condition {
    path_pattern {
      values = ["*"]
    }
  }
  action {
    type = "forward"
    target_group_arn = aws_lb_target_group.asg.arn
  }
}

resource "aws_autoscaling_group" "example" {
  launch_configuration = aws_launch_configuration.example.name
  vpc_zone_identifier = data.aws_subnets.example.ids

  target_group_arns = [aws_lb_target_group.asg.arn] # 어느 타겟 그룹으로 연결할지
  # 기본은 ec2
  # ASG가 대상 그룹의 상태 확인을 하여 인스턴스가 정상인지 여부를 판ㄷ별하고 대상 그룹의 상태가 불량하면 인스턴스를 자동으로 교체함
  health_check_type = "ELB"


  max_size = 10
  min_size = 2
  tag {
    key = "Name"
    value = "terraform-asg-example"  # 지정되는 태그의 값
    propagate_at_launch = true
  }
}

# ALB 자체를 생성
resource "aws_lb" "example" {
  name = "terraform-asg-example"
  load_balancer_type = "application"
#  subnets = data.aws_subnet_ids.default.ids
  subnets = data.aws_subnets.example.ids
  security_groups = [aws_security_group.alb.id]  # lb에서 사용할 보안그룹 정보 추가
}

# ALB에서 사용할 리스너를 정의
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.example.arn
  port = 80
  protocol = "HTTP"

  default_action {
    type = "fixed-response"  # 규칙이 일치하지 않은 요청에 대한 응답은 404로 정의
    fixed_response {
      content_type = "text/plain"
      message_body = "404:page not found"
      status_code = "404"
    }
  }
}

# ALB를 포함한 모든 AWS 리소스는 들어오는 트래픽과 나가는 트래픽을 허용하지 않으므로 ALB를 위한 보안 그룹 생성이 필요함
# 새로운 보안그룹은 80포트로 들어오는 요청을 허용하여 HTTP를 통해 로드밸런서에 접속할 수 있게 한다.
# 밖으로 나가는 요청은 포트와 상관없이 허용한다
resource "aws_security_group" "alb" {
  name = "terraform-example-alb"
  # 인바운드 트래픽 허용
  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # 모든 아웃바운드 트래픽 허용
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# aws_autoscaling_group에 타겟그룹을 명시해준다
resource "aws_lb_target_group" "asg" {
  name = "terraform-asg-example"
  port = var.server_port
  protocol = "HTTP"
  vpc_id = data.aws_vpc.default.id

  health_check {
    path = "/"
    protocol = "HTTP"
    matcher = "200"
    interval = 15
    timeout = 3
    healthy_threshold = 2
    unhealthy_threshold = 2
  }
}



variable "server_port" {
  description = "The port the server will use for hTTP requests"
  type = number
  default = 8080
}


# data 소스는 테라폼을 실행할 때마다 공급자에서 가져온 읽기 전용 정보임
# 단순히 데이터 공급자에게 API만 물어보고 해당 데이터를 나머지 테라폼 코드에서 사용할 수 있게 함
# 예를 들어, AWS 공급자에는 VPC 데이터, 서브넷 데이터, AMI ID,IP 주소 범위, 현재 사용자의 자격 증명 등을 조회하는 데이터 소스가 포함되어 있음
# 기본 vpc 정보 가져오기
data "aws_vpc" "default" {
  default = true
}

# 특정 VPC의 모든 서브넷 ID 가져오기
data "aws_subnets" "example" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

output "alb_dns_name" {
  value = aws_lb.example.dns_name
  description = "The domain name of the load balancer"
}