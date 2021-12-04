output "alb_dns_name" {
  value       = aws_lb.tutorial.dns_name
  description = "The domain name of the load balancer"
}

# output "vpc_id" {
#   value = module.vpc.vpc_id
# }