provider "aws" {
  region   = "ap-south-1"
  profile  = "goel"
}

resource "tls_private_key" "key_private" {
  algorithm = "RSA"
}

resource "aws_key_pair" "task_key" {
  key_name   = "task_key"
  public_key = "${tls_private_key.key_private.public_key_openssh}"
}

resource "aws_vpc" "myvpc" {
  cidr_block = "10.5.0.0/16"
  enable_dns_hostnames = true
  tags = {
    Name = "main"
  }
}

resource "aws_subnet" "wp-subnet" {
  vpc_id            = "${aws_vpc.myvpc.id}"
  availability_zone = "ap-south-1a"
  cidr_block        = "10.5.1.0/24"
  map_public_ip_on_launch = true
  tags = {
    Name = "wp-subnet"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = "${aws_vpc.myvpc.id}"
  tags = {
    Name = "wp-gw"
  }
}
resource "aws_route_table" "rtable" {
  vpc_id = "${aws_vpc.myvpc.id}"
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.gw.id}"
  }
  tags = {
    Name = "wp-rtable"
  }
}

resource "aws_route_table_association" "routea" {
  subnet_id      = aws_subnet.wp-subnet.id
  route_table_id = aws_route_table.rtable.id
}

resource "aws_security_group" "allow_http_wordpress" {
  name        = "allow_http_wordpress"
  description = "Allow HTTP inbound traffic"
  vpc_id      = "${aws_vpc.myvpc.id}"

  ingress {
    description = "Http from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }
  ingress {
    description = "SSH from VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "sgroup"
  }
}

   #subnet for mysql
resource "aws_subnet" "sql-subnet" {
  vpc_id            = "${aws_vpc.myvpc.id}"
  availability_zone = "ap-south-1b"
  cidr_block        = "10.5.2.0/24"
  tags = {
    Name = "sql-subnet"
  }
}

resource "aws_security_group" "mysql-sg" {
  name        = "mysql-sg"
  description = "MYSQL-setup"
  vpc_id      = "${aws_vpc.myvpc.id}"

  ingress {
    description = "MYSQL from VPC"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }
  ingress {
    description = "SSH from VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "sgroup"
  }
}


resource "aws_eip" "elastic_ip" {
  vpc      = true
}

resource "aws_nat_gateway" "nat_gw" {
  allocation_id = "${aws_eip.elastic_ip.id}"
  subnet_id     = "${aws_subnet.wp-subnet.id}"
  depends_on    = [ "aws_internet_gateway.gw" ]
}

resource "aws_route_table" "nat-rtable" {
  vpc_id = "${aws_vpc.myvpc.id}"
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_nat_gateway.nat_gw.id}"
  }
  tags = {
    Name = "nat-routetable"
  }
}

resource "aws_route_table_association" "nat-b" {
  subnet_id      = aws_subnet.sql-subnet.id
  route_table_id = aws_route_table.nat-rtable.id
}


resource "aws_security_group" "bastion-sg" {
  name        = "bastion-sg"
  description = "SSH to bastion-host"
  vpc_id      = "${aws_vpc.myvpc.id}"
  
  ingress {
    description = "SSH from VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "sgroup"
  }
}



#instance for wp and mysql
resource "aws_instance" "wordpress" {
  ami           = "ami-0d98b51fb579f2f18"
  instance_type = "t2.micro"
  key_name      = "task_key"
  availability_zone = "ap-south-1a"
  subnet_id     = "${aws_subnet.wp-subnet.id}"
  security_groups = [ "${aws_security_group.allow_http_wordpress.id}" ]
  tags = {
    Name = "Wordpress"
  }
}

resource "aws_instance" "mysql" {
  ami           = "ami-017692e888f7e7e43"
  instance_type = "t2.micro"
  key_name      = "task_key"
  availability_zone = "ap-south-1b"
  subnet_id     = "${aws_subnet.sql-subnet.id}"
  security_groups = [ "${aws_security_group.mysql-sg.id}" ]
  tags = {
    Name = "MYSQL"
  }
}


#instance for "Bastion-host
resource "aws_instance" "bastion-host" {
  ami           = "ami-00b494a3f139ba61f"
  instance_type = "t2.micro"
  key_name      = "task_key"
  availability_zone = "ap-south-1a"
  subnet_id     = "${aws_subnet.wp-subnet.id}"
  vpc_security_group_ids = [ "${aws_security_group.bastion-sg.id}" ]
  tags = {
    Name = "bastion-host"
  }
}

resource "null_resource" "save_key_pair"  {
	provisioner "local-exec" {
	    command = "echo  '${tls_private_key.key_private.private_key_pem}' > key.pem"
  	}
}

output "key-pair" {
  value = tls_private_key.key_private.private_key_pem
}