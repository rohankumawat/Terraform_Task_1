## Task1: Create/Launch and application using Terraform

![Image of Terraform and AWS](https://p2zk82o7hr3yb6ge7gzxx4ki-wpengine.netdna-ssl.com/wp-content/uploads/terraform-x-aws-1.png)

### Pre-Requisites: 
* AWS knowledge
* AWS CLI with Amazon AWS account
* Terraform CLI 
* GitHub Repo

### Problem Statement
1. Create the private key and security group which allows the port 80.
2. Launch Amazon AWS EC2 instance.
3. In this EC2 instance use the key and security group which we have created in step 1 to log-in remote or local.
4. Launch one Volume (EBS) and mount that volume into /var/www/html
5. The developer has uploaded the code into GitHub repo also the repo has some images.
6. Copy the GitHub repo code into /var/www/html
7. Create an S3 bucket, and copy/deploy the images from GitHub repo into the s3 bucket and change the permission to public readable.
8. Create a Cloudfront using S3 bucket(which contains images) and use the Cloudfront URL to update in code in /var/www/html

Let's start with the task!

**Step 1: Configuring AWS with Terraform**

After creating a profile on AWS using our CLI, we've to write the Terraform code. Here, we'll make a folder and keep everything in that folder. So, after giving any name to the file and keeping the extension '.tf', first we've to provide the AWS provider so that our Terraform code will know to contact to which service it wants! (In this case, we're providing Terraform the AWS provider so that it can interact with Amazon web services). 
To know more about **Providers**, [click here.](https://www.terraform.io/docs/providers/index.html)

```
provider "aws" {
  profile = "d2z-test"
  region  = "ap-south-1"
}
```

**Step 2: Creating private key and generating key-value pair**

To create a private key, we'll use Terraform's [tls_private_key](https://www.koding.com/docs/terraform/providers/tls/r/private_key.html/) resource. After creating the private key, we'll generate the key-pair using [aws_key_pair](https://www.terraform.io/docs/providers/aws/r/key_pair.html) resource which depends on our private key!

```
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
```

**Step 3: Creating the security group**

The security group in AWS acts as a firewall, after setting up the inbound and outbound rules  it will allow connections from and to particular ip addresses. We'll use [aws_security_group](https://www.terraform.io/docs/providers/aws/r/security_group.html) recource to create the secutiry group.

```
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
```

**Step 4: Creating our EC2 instance**

We always need an instance so that we can write our code there and then can use it to deploy our application. So, to do so we can use any instance but here I've used "Amazon Linux 2 AMI" with t2.micro instance type. We'll use [aws_instance](https://www.terraform.io/docs/providers/aws/r/instance.html) resource to create our AWS instance.

```
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
```

**Step 5: Creating and attaching the EBS volume to the Instance**

To create an EBS volume, we'll use [aws_ebs_volume](https://www.terraform.io/docs/providers/aws/r/ebs_volume.html) resource. After creating the EBS volume, all that left is attaching to the EC2 instance and mounting it to the /var/www/html folder. So to do so, we'll use terraform's [aws_volume_attachement](https://www.terraform.io/docs/providers/aws/r/volume_attachment.html) resource.


```
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
```

**Step 6: Write the code and upload to GitHub**

Here I wrote a small PHP code which will print the 'ifconfig' command's output on the webpage and then uploaded it on the GitHub.

**Step 7: Creating S3 bucket and uploading an image**

We'll use S3 bucket static content of the webpage to create the bucket using Terraform's [aws_s3_bucket](https://www.terraform.io/docs/providers/aws/r/s3_bucket.html) resource. 

```
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
```

**Step 8: Creating the Cloud Front distribution**

We'll use Terraform's [aws_cloudfront_distribution](https://www.terraform.io/docs/providers/aws/r/cloudfront_distribution.html) resource.

```
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
```

**Step 9: Adding the image to our WebPage**

```
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
```

Now it's time to run few a commands in CMD and then we're done with deploying a webserver on AWS cloud using Terraform!

```
terraform init
terraform validate 
terraform plan
terraform apply --auto-approve
```
![Terraform apply](https://github.com/rohankumawat/Terraform_Task_1/blob/master/Screenshots/Screenshot%20(442).png)
### Launching the application 

![Application](https://github.com/rohankumawat/Terraform_Task_1/blob/master/Screenshots/Screenshot%20(440).png)

**Woah! That's all.**
