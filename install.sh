for script in ./tools/preinstall/*.sh; do
  /bin/bash "$script"
done

# my aws home
echo 'export AWS_DEFAULT_REGION=us-west-2' >> ~/.bashrc
