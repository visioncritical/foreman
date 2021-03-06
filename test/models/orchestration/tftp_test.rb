require 'test_helper'

class TFTPOrchestrationTest < ActiveSupport::TestCase
  setup :disable_orchestration

  context 'host without tftp orchestration' do
    setup do
      @host = FactoryGirl.create(:host)
    end

    test 'should not have any tftp' do
      skip_without_unattended
      assert_equal false, @host.tftp?
      assert_equal false, @host.tftp6?
      assert_nil @host.tftp
      assert_nil @host.tftp6
    end

    test '#setTFTP should not call any tftp proxy' do
      ProxyAPI::TFTP.any_instance.expects(:set).never
      @host.provision_interface.stubs(:generate_pxe_template).returns('Template')
      @host.provision_interface.send(:setTFTP, 'PXEGrub2')
    end

    test 'should not queue tftp' do
      @host.provision_interface.send(:queue_tftp)
      tasks = @host.queue.all.map { |t| t.name }
      assert_empty tasks
    end
  end

  context 'host with ipv4 tftp' do
    setup do
      @host = FactoryGirl.build(:host, :managed, :with_tftp_orchestration, :build => true)
    end

    test 'should have tftp' do
      skip_without_unattended
      assert @host.tftp?
      refute @host.tftp6?
      assert_not_nil @host.tftp
      assert_nil @host.tftp6
    end

    test '#setTFTP should call one tftp proxy' do
      ProxyAPI::TFTP.any_instance.expects(:set).once
      @host.provision_interface.stubs(:generate_pxe_template).returns('Template')
      @host.provision_interface.send(:setTFTP, 'PXEGrub2')
    end

    test 'should queue tftp' do
      @host.provision_interface.send(:queue_tftp)
      tasks = @host.queue.all.map { |t| t.name }
      assert_includes tasks, "Deploy TFTP PXEGrub config for #{@host.provision_interface}"
      assert_includes tasks, "Fetch TFTP boot files for #{@host.provision_interface}"
    end

    test "without pxe loader should not have tftp" do
      skip_without_unattended
      @host.expects(:pxe_loader).returns('').at_least(1)
      assert_equal false, @host.tftp?
      assert_nil @host.tftp
    end
  end

  context 'host with ipv6 tftp' do
    setup do
      @host = FactoryGirl.build(:host, :managed, :with_tftp_v6_orchestration, :build => true)
    end

    test "should have ipv6 tftp" do
      skip_without_unattended
      refute @host.tftp?
      assert @host.tftp6?
      assert_nil @host.tftp
      assert_not_nil @host.tftp6
      assert_nil @host.subnet
    end

    test '#setTFTP should call one tftp proxy' do
      ProxyAPI::TFTP.any_instance.expects(:set).once
      @host.provision_interface.stubs(:generate_pxe_template).returns('Template')
      @host.provision_interface.send(:setTFTP, 'PXEGrub2')
    end

    test 'should queue tftp' do
      @host.provision_interface.send(:queue_tftp)
      tasks = @host.queue.all.map { |t| t.name }
      assert_includes tasks, "Deploy TFTP PXEGrub config for #{@host.provision_interface}"
      assert_includes tasks, "Fetch TFTP boot files for #{@host.provision_interface}"
    end
  end

  context 'host with ipv4 and ipv6 tftp' do
    setup do
      @host = FactoryGirl.build(:host, :managed, :with_tftp_dual_stack_orchestration, :build => true)
    end

    test "host should have ipv4 and ipv6 tftp" do
      skip_without_unattended
      assert @host.tftp?
      assert @host.tftp6?
      assert_not_nil @host.tftp
      assert_not_nil @host.tftp6
    end

    test '#setTFTP should call both tftp proxies' do
      ProxyAPI::TFTP.any_instance.expects(:set).twice
      @host.provision_interface.stubs(:generate_pxe_template).returns('Template')
      @host.provision_interface.send(:setTFTP, 'PXEGrub2')
    end

    test '#setTFTP should call just one proxy if the proxies are unique' do
      ProxyAPI::TFTP.any_instance.expects(:set).once
      @host.provision_interface.stubs(:generate_pxe_template).returns('Template')
      @host.provision_interface.subnet6.tftp = @host.provision_interface.subnet.tftp
      assert @host.provision_interface.subnet6.save!
      @host.provision_interface.send(:setTFTP, 'PXEGrub2')
    end

    test 'should queue tftp' do
      @host.provision_interface.send(:queue_tftp)
      tasks = @host.queue.all.map { |t| t.name }
      assert_includes tasks, "Deploy TFTP PXEGrub config for #{@host.provision_interface}"
      assert_includes tasks, "Fetch TFTP boot files for #{@host.provision_interface}"
    end
  end

  context 'host with bond interface' do
    let(:subnet) do
      FactoryGirl.build(:subnet_ipv4, :tftp, :with_taxonomies)
    end
    let(:interfaces) do
      [
        FactoryGirl.build(:nic_bond, :primary => true,
                          :identifier => 'bond0',
                          :attached_devices => ['eth0', 'eth1'],
                          :provision => true,
                          :domain => FactoryGirl.build(:domain),
                          :subnet => subnet,
                          :mac => nil,
                          :ip => subnet.network.sub(/0\Z/, '2')),
        FactoryGirl.build(:nic_interface,
                          :identifier => 'eth0',
                          :mac => '00:53:67:ab:dd:00'
                         ),
        FactoryGirl.build(:nic_interface,
                          :identifier => 'eth1',
                          :mac => '00:53:67:ab:dd:01'
                         )
      ]
    end
    let(:host) do
      FactoryGirl.create(:host,
                         :with_tftp_orchestration,
                         :subnet => subnet,
                         :interfaces => interfaces,
                         :build => true,
                         :location => subnet.locations.first,
                         :organization => subnet.organizations.first)
    end

    test '#setTFTP should provision tftp for all bond child macs' do
      ProxyAPI::TFTP.any_instance.expects(:set).with(
        'PXEGrub2',
        '00:53:67:ab:dd:00',
        {:pxeconfig => 'Template'}
      ).once
      ProxyAPI::TFTP.any_instance.expects(:set).with(
        'PXEGrub2',
        '00:53:67:ab:dd:01',
        {:pxeconfig => 'Template'}
      ).once
      host.provision_interface.stubs(:generate_pxe_template).returns('Template')
      host.provision_interface.send(:setTFTP, 'PXEGrub2')
    end
  end

  test 'unmanaged should not call methods after managed?' do
    if unattended?
      h = FactoryGirl.create(:host)
      Nic::Managed.any_instance.expects(:provision?).never
      assert h.valid?
      assert_equal false, h.tftp?
    end
  end

  test "generate_pxe_template_for_pxelinux_build" do
    return unless unattended?
    h = FactoryGirl.build(:host, :managed, :build => true,
                          :operatingsystem => operatingsystems(:redhat),
                          :architecture => architectures(:x86_64))
    h.organization.update_attribute :ignore_types, h.organization.ignore_types + ['ProvisioningTemplate']
    h.location.update_attribute :ignore_types, h.location.ignore_types + ['ProvisioningTemplate']
    Setting[:unattended_url] = "http://ahost.com:3000"

    template = h.send(:generate_pxe_template, :PXELinux).to_s.gsub! '~', "\n"
    expected = <<-EXPECTED
default linux
label linux
kernel boot/Redhat-6.1-x86_64-vmlinuz
append initrd=boot/Redhat-6.1-x86_64-initrd.img ks=http://ahost.com:3000/unattended/kickstart ksdevice=bootif network kssendmac
EXPECTED
    assert_equal template,expected.strip
    assert h.build
  end

  test "generate_pxe_template_for_pxelinux_localboot" do
    return unless unattended?
    h = FactoryGirl.create(:host, :managed)
    as_admin { h.update_attribute :operatingsystem, operatingsystems(:centos5_3) }
    assert !h.build

    template = h.send(:generate_pxe_template, :PXELinux).to_s.gsub! '~', "\n"
    expected = <<-EXPECTED
DEFAULT menu
PROMPT 0
MENU TITLE PXE Menu
TIMEOUT 200
TOTALTIMEOUT 6000
ONTIMEOUT local

LABEL local
MENU LABEL (local)
MENU DEFAULT
LOCALBOOT 0
EXPECTED
    assert_equal template,expected.strip
  end

  test "generate_default_pxe_template_for_pxelinux_localboot_from_setting" do
    return unless unattended?
    template = FactoryGirl.create(:provisioning_template, :name => 'my template',
                                                          :template => 'test content',
                                                          :template_kind => template_kinds(:pxelinux))
    Setting['local_boot_PXELinux'] = template.name
    h = FactoryGirl.create(:host, :managed)
    as_admin { h.update_attribute :operatingsystem, operatingsystems(:centos5_3) }
    assert !h.build

    result = h.send(:generate_pxe_template, :PXELinux)
    assert_equal template.template, result
  end

  test "generate_default_pxe_template_for_pxelinux_localboot_from_param" do
    return unless unattended?
    template = FactoryGirl.create(:provisioning_template, :name => 'my template',
                                                          :template => 'test content again',
                                                          :template_kind => template_kinds(:pxelinux))
    h = FactoryGirl.create(:host, :managed)
    param = FactoryGirl.create(:host_parameter, :name => 'local_boot_PXELinux', :value => template.name, :reference_id => h.id)
    as_admin { h.update_attribute :operatingsystem, operatingsystems(:centos5_3) }
    assert !h.build

    result = h.send(:generate_pxe_template, :PXELinux)
    assert_equal template.template, result
  end

  test 'should rebuild tftp IPv4' do
    host = FactoryGirl.create(:host, :with_tftp_orchestration)
    Nic::Managed.any_instance.expects(:setTFTP).with('PXELinux').once.returns(true)
    Nic::Managed.any_instance.expects(:setTFTP).with('PXEGrub').once.returns(true)
    Nic::Managed.any_instance.expects(:setTFTP).with('PXEGrub2').once.returns(true)
    assert host.interfaces.first.rebuild_tftp
  end

  test 'should rebuild tftp IPv6' do
    host = FactoryGirl.create(:host, :with_tftp_v6_orchestration)
    Nic::Managed.any_instance.expects(:setTFTP).with('PXELinux').once.returns(true)
    Nic::Managed.any_instance.expects(:setTFTP).with('PXEGrub').once.returns(true)
    Nic::Managed.any_instance.expects(:setTFTP).with('PXEGrub2').once.returns(true)
    assert host.interfaces.first.rebuild_tftp
  end

  describe "validation" do
    setup do
      @host = FactoryGirl.create(:host, :with_tftp_orchestration)
      @host.stubs(:provisioning_template).returns(nil)
      @host.pxe_loader = nil
    end

    test "should not fail without PXE loader" do
      skip_without_unattended
      @host.interfaces.first.send(:validate_tftp)
      assert_nil @host.errors[:base].first
    end

    test "should not fail with None PXE loader" do
      skip_without_unattended
      @host.pxe_loader = ""
      @host.interfaces.first.send(:validate_tftp)
      assert_nil @host.errors[:base].first
    end

    test "should fail without PXEGrub2 kind" do
      skip_without_unattended
      @host.pxe_loader = "grub2/grubx64.efi"
      @host.interfaces.first.send(:validate_tftp)
      assert_match /^No PXEGrub2 templates were found.*/, @host.errors[:base].first
    end

    test "should fail without PXEGrub kind" do
      skip_without_unattended
      @host.pxe_loader = "grub/bootx64.efi"
      @host.interfaces.first.send(:validate_tftp)
      assert_match /^No PXEGrub templates were found.*/, @host.errors[:base].first
    end

    test "should fail without PXELinux kind" do
      skip_without_unattended
      @host.pxe_loader = "pxelinux.0"
      @host.interfaces.first.send(:validate_tftp)
      assert_match /^No PXELinux templates were found.*/, @host.errors[:base].first
    end
  end

  test "should_fail_rebuild_tftp_with_exception" do
    h = FactoryGirl.create(:host, :with_tftp_orchestration)
    Nic::Managed.any_instance.expects(:setTFTP).with('PXELinux').raises(StandardError, 'TFTP rebuild failed')
    Nic::Managed.any_instance.expects(:setTFTP).with('PXEGrub').once.returns(true)
    Nic::Managed.any_instance.expects(:setTFTP).with('PXEGrub2').once.returns(true)
    refute h.interfaces.first.rebuild_tftp
  end

  test "should_skip_rebuild_tftp" do
    nic = FactoryGirl.build(:nic_managed)
    nic.expects(:setTFTP).never
    assert nic.rebuild_tftp
  end

  test "generate_pxelinux_template_for_suse_build" do
    return unless unattended?
    h = FactoryGirl.build(:host, :managed, :build => true,
                          :operatingsystem => operatingsystems(:opensuse),
                          :architecture => architectures(:x86_64))
    Setting[:unattended_url] = "http://ahost.com:3000"
    h.organization.update_attribute :ignore_types, h.organization.ignore_types + ['ProvisioningTemplate']
    h.location.update_attribute :ignore_types, h.location.ignore_types + ['ProvisioningTemplate']

    template = h.send(:generate_pxe_template, :PXELinux).to_s.gsub! '~', "\n"
    expected = <<-EXPECTED
DEFAULT linux
LABEL linux
KERNEL boot/OpenSuse-12.3-x86_64-linux
APPEND initrd=boot/OpenSuse-12.3-x86_64-initrd ramdisk_size=65536 install=http://download.opensuse.org/distribution/12.3/repo/oss autoyast=http://ahost.com:3000/unattended/provision textmode=1
EXPECTED
    assert_equal template,expected.strip
    assert h.build
  end
end
