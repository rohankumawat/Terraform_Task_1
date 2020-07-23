// describing provider

provider "aws" {
  profile = "d2z-test"
  region  = "ap-south-1"
}

// creating a private key

resource "tls_private_key" "taskkey" {
  algorithm = "RSA"
}

// generating key-value pair

resource "aws_key_pair" "keypair" {
  key_name = "t1keypair"
  public_key = tls_private_key.taskkey.public_key_openssh
  depends_on = [
    tls_private_key.taskkey 
  ]
}

//creating the security group

resource "aws_security_group" "allow_tls" {
  name        = "t1sg"
  description = "Allow SSH and Port 80"

  // for HTTP
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  // for SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "task1firewall"
  }
}

// creating ec2 instance

resource "aws_instance" "ec2ins" {
  ami           = "ami-0732b62d310b80e97"
  instance_type = "t2.micro"
  key_name      = aws_key_pair.keypair.key_name
  security_groups = ["${aws_security_group.allow_tls.name}","default"]

  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.taskkey.private_key_pem
    host     = aws_instance.ec2ins.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd php git -y",
      "sudo systemctl start httpd",
      "sudo systemctl enable httpd",
    ]
  }

  ebs_block_device {
    device_name = "/dev/xvda"
    volume_size = "8"
    volume_type = "gp2"
  }

  tags = {
    Name = "HybridTask1"
  }

  depends_on = [
    aws_key_pair.keypair
  ]
}

// creating EBS volume

resource "aws_ebs_volume" "ebsvol" {
  availability_zone = aws_instance.ec2ins.availability_zone
  size              = 4

  tags = {
    Name = "EBStask1"
  }

  depends_on = [
      aws_instance.ec2ins
  ]
}

// attaching EBS volume

resource "aws_volume_attachment" "ebs_att" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.ebsvol.id
  instance_id = aws_instance.ec2ins.id
  force_detach = true

  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.taskkey.private_key_pem
    host     = aws_instance.ec2ins.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4  /dev/xvdf",
      "sudo mount  /dev/xvdf  /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/rohankumawat/Terraform_Task_1.git /var/www/html/"
    ]
  }

  depends_on = [
	aws_instance.ec2ins
]
}

// creating s3 bucket

resource "aws_s3_bucket" "task1bucket" {
  bucket = "s3buckett1"
  acl    = "public-read"

  tags = {
    Name        = "Task 1 Bucket"
  }
}

// uploading image to s3

resource "aws_s3_bucket_object" "object" {
  bucket = aws_s3_bucket.task1bucket.bucket
  key    = "Woahhh.jpg"
  source = "D:/HybridCloudTasks/Woahhh.jpg"
  content_type = "image/jpg"
  acl = "public-read"
  depends_on = [
	aws_s3_bucket.task1bucket
]
}

// creating cloud front distribution

locals {
  s3_origin_id = "s3task1"
}

resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = aws_s3_bucket.task1bucket.bucket_regional_domain_name
    origin_id   = local.s3_origin_id
  }

  enabled             = true
  is_ipv6_enabled     = true

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Environment = "task1"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  depends_on = [
    aws_s3_bucket_object.object
  ]
}

// adding image to the webpage

resource "null_resource" "cluster" {
  depends_on = [
    aws_instance.ec2ins, aws_cloudfront_distribution.s3_distribution, aws_volume_attachment.ebs_att
  ]

  connection {
    type = "ssh"
    user = "ec2-user"
    private_key = tls_private_key.taskkey.private_key_pem
    host     = aws_instance.ec2ins.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "echo '<img src='https://${aws_cloudfront_distribution.s3_distribution.domain_name}/Woahhh.jpg'>'  | sudo tee -a /var/www/html/index.php"
    ]
  }
}