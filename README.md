# Virt-patch

Ever needed to not only list the changes between two disk images, but actually fetch the changed files and directories or apply the changes to an unpatched disk image? Look no further!

Since this script was built from two smaller, less generic scripts with a clear use case in mind (being a [Blackhat 2019 Training](https://www.blackhat.com/us-19/)), it might require some work to fit your situation. Feel free to create pull requests to make it more generic.

Tested on Ubuntu 18.04 and Kali 2019.2.

## Requisites

* [virt-diff](http://libguestfs.org/virt-diff.1.html)
* [guestmount](http://libguestfs.org/guestmount.1.html)
* [rsync](https://linux.die.net/man/1/rsync)

## Usage

When downloaded, first make the script executable:

`chmod u+x virt-patch.sh`

To fetch all changed directories and files, run it like this:

`./virt-patch.sh --fetch bustakube-OLD.qcow2 bustakube-NEW.qcow2`

To only list the changes between two disk images, run it like this:

`./virt-patch.sh --list bustakube-OLD.qcow2 bustakube-NEW.qcow2`

To patch an unpatched disk image, run it like this:

`./virt-patch.sh --patch bustakube-OLD.qcow2`

This tool will find differences in filenames, file sizes, checksums, extended attributes, file content and more from a virtual machine or disk image. However it __does not__ look at the boot loader, unused space between partitions or within filesystems, "hidden" sectors and so on. In other words, it is not a security or forensics tool.

## Thanks!

A special thanks to @jaybeale from [InGuardians](https://InGuardians.com) for challenging me during Blackhat 2019 Training 'A PURPLE TEAM VIEW - ATTACKING AND DEFENDING LINUX, DOCKER, AND KUBERNETES'. If it wasn't for you, this script would not have been created and over a hundred students would've needed to copy over a 12GB disk image.