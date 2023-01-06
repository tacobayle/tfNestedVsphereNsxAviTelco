data "template_file" "template_patching" {
  template = file("templates/workload_cluster_patching.sh.template")
  count = length(var.tkg.clusters.workloads)
  vars = {
    name = var.tkg.clusters.workloads[count.index].name
    file_ips = "${var.tkg.clusters.workloads[count.index].name}-${count.index + 1}.txt"
    private_key=basename(var.tkg.clusters.workloads[count.index].private_key_path)
    username = var.external_gw.username
    ssh_username = var.tkg.clusters.workloads[count.index].ssh_username
  }
}

resource "null_resource" "workload_patching" {
  count = length(var.tkg.clusters.workloads)
  connection {
    host        = var.vcenter.dvs.portgroup.management.external_gw_ip
    type        = "ssh"
    agent       = false
    user        = var.external_gw.username
    private_key = file(var.external_gw.private_key_path)
  }

  provisioner "remote-exec" {
    inline = [
      "mkdir workload_patching_${count.index + 1}"
    ]
  }


  provisioner "file" {
    content = data.template_file.template_patching[count.index].rendered
    destination = "/home/${var.external_gw.username}/workload_patching_${count.index + 1}/patching${count.index + 1}.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "/bin/bash /home/${var.external_gw.username}/workload_patching_${count.index + 1 }/patching${count.index + 1 }.sh"
    ]
  }
  
}