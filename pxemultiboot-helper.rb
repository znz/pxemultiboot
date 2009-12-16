#!/usr/bin/ruby
# -*- coding: utf-8 -*-
=begin
= PXE Multi Boot Helper
== Requirements
* Ruby 1.8.x or later
* wget

== Usage
* ruby pxemultiboot-helper.rb --help
* ruby pxemultiboot-helper.rb --debian lenny,etch,etchnhalf,squeeze,sid --ubuntu karmic,hardy,jaunty,intrepid,dapper,lucid --fedora 12,11,10,9 --centos 5.4,5.3,4.8,4.7 --vine 5.0,4.2 --mbm 0.39 --plop-boot-manager 5.0.4 --freedos-balder10 --gag 4.10 --ping 3.00.03


== License
The MIT License

Copyright (c) 2009 Kazuhiro NISHIYAMA

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
=end

require "fileutils"
require "optparse"

class PxeMultiBootHelper
  def initialize
    setup_default_mirror
    set_top_dir
    set_verbose
  end

  def setup_default_mirror
    @mirror = {
      :syslinux => "http://www.kernel.org/pub/linux/utils/boot/syslinux",

      :debian => "http://ftp.jp.debian.org/debian",
      :ubuntu => "http://jp.archive.ubuntu.com/ubuntu",

      # see http://mirrors.fedoraproject.org/publiclist/Fedora/
      :fedora => "http://ftp.riken.jp/Linux/fedora/releases",
      :centos => "http://ftp.riken.jp/Linux/centos",
      :vine => "http://ftp.vinelinux.org/pub/Vine",
      #:vine => "http://www.t.ring.gr.jp/pub/linux/Vine",

      :ping_release => "http://ping.windowsdream.com/ping/Releases",
      :plop_files => "http://download.plop.at/files/bootmngr",
      :balder10_img => "http://www.finnix.org/files/balder10.img",
      :mbm_zip => "http://my.vector.co.jp/servlet/System.FileDownload/download/http/0/35596/pack/dos/util/boot/mbm039.zip",
      :gag_zip => "http://downloads.sourceforge.net/gag/gag%s.zip",
    }
  end

  def mirror(target)
    @mirror[target]
  end

  def set_verbose(flag=true)
    if flag
      @verbose = true
      @fu = ::FileUtils::Verbose
    else
      @verbose = false
      @fu = ::FileUtils
    end

    def @fu.cp(src, dest, options={})
      options[:preserve] = true # always preserve
      super(src, dest, options)
    end
  end

  def set_top_dir(top_dir='.')
    @tftpboot_dir = File.expand_path('tftpboot', top_dir)
    @download_dir = File.expand_path('download', top_dir)
    @boot_screens = File.join(tftpboot_dir, "boot-screens")
  end

  attr_reader :fu
  attr_reader :tftpboot_dir, :download_dir, :boot_screens

  def setup_directories
    fu.mkpath(download_dir) unless File.directory?(download_dir)
    fu.mkpath(boot_screens) unless File.directory?(boot_screens)
    fu.chdir(tftpboot_dir)
  end

  def xsystem(*args)
    puts "system(#{args.inspect})"
    system(*args)
  end

  def download(path, uri)
    unless File.exist?(path)
      unless xsystem("wget", uri, "-O", path)
        fu.rm_f(path)
        raise "download failed: #{uri} to #{path}"
      end
    end
  end

  class Menu
    def initialize(menu_cfg)
      @menu_cfg = menu_cfg
      @sub_menus = []
    end

    def push_sub_menu(menu)
      @sub_menus.push(menu)
    end

    def cfg_puts(cfg_text)
      @menu_cfg_file.puts cfg_text if cfg_text
    end

    def menu_include(sub_cfg)
      cfg_puts "include #{sub_cfg}"
    end

    def run(parent, top)
      open(@menu_cfg, "w") do |f|
        @menu_cfg_file = f
        cfg_puts cfg_prologue
        main(parent, top)
        cfg_puts cfg_epilogue
      end
    ensure
      @menu_cfg_file = nil
    end

    def main(parent, top)
      @sub_menus.each do |sub_menu|
        sub_menu.run(self, top)
      end
      parent.menu_include @menu_cfg
    end

    def cfg_prologue
      <<-CFG
label mainmenu
	menu label ^Return to Top Menu
	kernel boot-screens/vesamenu.c32
	append pxelinux.cfg/default
      CFG
    end

    def cfg_epilogue
      nil
    end
  end

  def menu_include(top_menu_cfg)
    # ignore
  end

  class TopMenu < Menu
    def cfg_prologue
      <<-CFG
menu hshift 5
menu width 65

menu title PXE Boot Menu
menu background boot-screens/syslinux_splash.jpg
      CFG
    end
  end

  class Installer < Menu
    def initialize(distro, title)
      @distro = distro
      @title = title
      super("boot-screens/#{@distro}.cfg")
    end

    def cfg_prologue
      <<-CFG
menu begin #{@title} Install
	menu title #{@title} Install
	label mainmenu
		menu label ^Back..
		menu exit
      CFG
    end

    def cfg_epilogue
      "menu end"
    end
  end

  class DebianInstaller < Menu
    def initialize(suite, title, options={})
      @title = title
      @arch = options[:arch] || "i386"

      if options[:installer_suite]
        @target_suite = suite
        @installer_suite = options[:installer_suite]
      else
        @target_suite = suite
        @installer_suite = suite
      end

      if options[:gtk]
        @m_gtk = "-gtk" # minus and gtk
        @slash_gtk = "/gtk" # slash and gtk
        @s_GTK = " GTK" # space and GTK
      else
        @m_gtk = @slash_gtk = @s_GTK = ""
      end

      super("boot-screens/#{@target_suite}-#{@arch}#{@m_gtk}.cfg")
    end

    def distro
      "debian"
    end

    def mirror(top)
      top.mirror(:debian)
    end

    def extract_dir
      "#{distro}-installer"
    end

    def installer_dir
      "#{distro}/#{@installer_suite}#{@m_gtk}-installer"
    end

    def netboot_uri(top)
      "#{mirror(top)}/dists/#{@installer_suite}/main/installer-#{@arch}/current/images/netboot#{@slash_gtk}/netboot.tar.gz"
    end

    def netboot_tar_gz(top)
      "#{top.download_dir}/#{@installer_suite}-#{@arch}#{@m_gtk}-netboot.tar.gz"
    end

    def main(parent, top)
      fu = top.fu

      top.download(netboot_tar_gz(top), netboot_uri(top))
      fu.mkpath("tmp")
      fu.chdir("tmp") do
        top.xsystem("tar", "xf", netboot_tar_gz(top), "./#{extract_dir}/")
      end
      fu.mkpath(installer_dir)
      fu.rm_rf("#{installer_dir}/#{@arch}")
      fu.mv("tmp/#{extract_dir}/#{@arch}", "#{installer_dir}/")
      fu.rmdir("tmp/#{extract_dir}")
      fu.rmdir("tmp")

      menu_cfg = "#{installer_dir}/#{@arch}/boot-screens/menu.cfg"
      if File.exist?(menu_cfg)
        # interpid, jaunty
        # lenny
        proc_cfg_file = proc do |cfg_filename|
          File.foreach(cfg_filename) do |line|
            line.gsub!(extract_dir) { installer_dir }
            if /\s*include (\S+)/ =~ line
              if File.exist?($1)
                cfg_puts '#^^^ ' + line
                proc_cfg_file.call($1)
                cfg_puts '#$$$ ' + line
              else
                cfg_puts '#### ' + line
              end
            else
              cfg_puts line
            end
          end
        end
        proc_cfg_file.call(menu_cfg)
      else
        # dapper, hardy
        # etch
        File.foreach("#{installer_dir}/#{@arch}/pxelinux.cfg/default") do |line|
          case line
          when /^LABEL /
            cfg_puts "label #{@target_suite}-#{@arch}-#{$'}"
          when /^\s+(?:kernel|append)/
            cfg_puts line.gsub(extract_dir) { installer_dir }
          else
            # ignore
          end
        end
      end

      kernel = "#{@installer_suite}#{@m_gtk}-installer/#{@arch}/boot-screens/vesamenu.c32"
      unless File.exist?(kernel)
        kernel = "boot-screens/vesamenu.c32"
      end
      parent.cfg_puts <<-CFG
label #{@target_suite}-#{@arch}#{@m_gtk}
	menu label #{@title} #{@arch}#{@s_GTK} Installer
	kernel #{kernel}
	append boot-screens/#{@target_suite}-#{@arch}#{@m_gtk}.cfg
      CFG
    end
  end # DebianInstaller


  class DebianAndAHalfInstaller < DebianInstaller
    def initialize(suite, title, options={})
      options[:installer_suite] = "lenny"
      super
    end

    def cfg_puts(cfg_text)
      return unless cfg_text
      cfg_text.gsub!(/^\s*append.+(?= --)/) { $& + " suite=etch" }
      @menu_cfg_file.puts cfg_text
    end
  end # DebianAndAHalfInstaller

  class Ubuntu < DebianInstaller
    def distro
      "ubuntu"
    end

    def mirror(top)
      top.mirror(:ubuntu)
    end
  end

  class Anaconda < Menu
    def initialize(options)
      @distro = options[:distro]
      @title = options[:title]
      @ver = options[:ver]
      @arch = options[:arch]
      @kernel = options.fetch(:kernel, "images/pxeboot/vmlinuz")
      @initrd = options.fetch(:initrd, "images/pxeboot/initrd.img")
      @isolinux_cfg = options.fetch(:isolinux_cfg, "isolinux/isolinux.cfg")
      @template = options[:template]
      @append_template = options.fetch(:append_template, nil)
      d_v_a = "#{@distro}-#{@ver}-#{@arch}"
      super("boot-screens/#{d_v_a}.cfg")
    end

    def mirror(top)
      top.mirror(@distro.intern)
    end

    def main(parent, top)
      fu = top.fu
      d_v_a_dir = "#{@distro}/#{@ver}/#{@arch}"
      d_v_a = "#{@distro}-#{@ver}-#{@arch}"
      fu.mkpath(d_v_a_dir)
      download_dir = "#{top.download_dir}/#{d_v_a}"
      fu.mkpath(download_dir)
      [@kernel, @initrd, @isolinux_cfg].each do |file|
        download_file = "#{download_dir}/#{File.basename(file)}"
        uri = sprintf(@template, mirror(top), @ver, @arch, file)
        top.download(download_file, uri)
        fu.cp(download_file, "#{d_v_a_dir}/#{File.basename(file)}")
      end
      cfg = File.read("#{download_dir}/#{File.basename(@isolinux_cfg)}")
      cfg.gsub!(/^(?:prompt|timeout)/) { '###'+$& }
      more_files = []
      menu_c32 = "boot-screens/vesamenu.c32"
      cfg.gsub!(/^(default|display|F\d|menu background|\s*kernel|KBDMAP) (vesamenu\.c32|\w+\.msg|splash\.jpg|memtest|jp106\.kbd)$/i) {
        more_files << $2
        if $1 == "default"
          menu_c32 = "#{d_v_a_dir}/#{$2}"
        end
        "#{$1} #{d_v_a_dir}/#{$2}"
      }
      if @append_template
        append = sprintf(@append_template, mirror(top), @ver, @arch)
        cfg.gsub!(/^\s*append.*initrd.*/) {
          "#{$&} #{append}"
        }
      end
      cfg.gsub!(/vmlinuz|initrd\.img/) {
        "#{d_v_a_dir}/#{$&}"
      }
      cfg.gsub!(/^\s*label /) { "#{$&}#{d_v_a}-" }
      more_files.each do |file|
        file = File.join(File.dirname(@isolinux_cfg), file)
        download_file = "#{download_dir}/#{File.basename(file)}"
        uri = sprintf(@template, mirror(top), @ver, @arch, file)
        top.download(download_file, uri)
        fu.cp(download_file, "#{d_v_a_dir}/#{File.basename(file)}")
      end
      cfg_puts cfg

      parent.cfg_puts <<-CFG
label #{d_v_a}
	menu label #{@title} #{@ver} #{@arch} Installer
	kernel #{menu_c32}
	append boot-screens/#{d_v_a}.cfg
      CFG
    end
  end # Anaconda

  # PING (Partimage Is Not Ghost) -- Backup and Restore Disk Partitions
  # http://ping.windowsdream.com/ping.html
  class PING < Menu
    TITLE = "PING(Partimage Is Not Ghost)"

    def initialize(ver)
      @name = "ping"
      @ver = ver
      @dir = "#{@name}-#{@ver}"
      super("boot-screens/#{@dir}.cfg")
    end

    def uri(file, top)
      "#{top.mirror(:ping_release)}/#{@ver}/#{file}"
    end

    def main(parent, top)
      fu = top.fu
      download_dir = "#{top.download_dir}/#{@dir}"
      fu.mkpath(download_dir)
      fu.mkpath(@dir)
      isolinux_cfg = "#{download_dir}/isolinux.cfg"
      top.download(isolinux_cfg, uri("isolinux.cfg", top))
      cfg = File.read(isolinux_cfg)
      more_files = ["initrd.gz"]
      cfg.gsub!(/^(DISPLAY|KERNEL) (\w+\.msg|kernel)$/) {
        more_files << $2
        "#{$1} #{@dir}/#{$2}"
      }
      cfg.gsub!(/initrd\.gz/) {
        "#{@dir}/#{$&}"
      }
      more_files.each do |file|
        download_file = "#{download_dir}/#{file}"
        top.download(download_file, uri(file, top))
        fu.cp(download_file, "#{@dir}/#{File.basename(file)}")
      end
      cfg_puts cfg
      parent.cfg_puts <<-CFG
label #{@dir}
	menu label #{TITLE} #{@ver}
	kernel boot-screens/vesamenu.c32
	append boot-screens/#{@dir}.cfg
      CFG
    end

    def cfg_prologue
      "menu title #{TITLE} #{@ver}"
    end

    def cfg_epilogue
      <<-CFG
label mainmenu
	menu label ^Return to Top Menu
	kernel boot-screens/vesamenu.c32
	append pxelinux.cfg/default
      CFG
    end
  end


  class SimpleMenu < Menu
    def initialize(name, ver)
      @name = name
      @ver = ver
      @dir = "#{@name}-#{@ver}"
      super("boot-screens/#{@dir}.cfg")
    end

    def main(parent, top)

      fu = top.fu
      download_uri = uri(top)
      download_file = "#{top.download_dir}/#{@name}/#{File.basename(download_uri)}"
      fu.mkpath(File.dirname(download_file))
      top.download(download_file, download_uri)
      fu.mkpath(@dir)

      main_after_download(download_file, parent, top)

      parent.menu_include @menu_cfg
    end

    def cfg_prologue
      nil
    end
  end

  # http://www.plop.at/en/bootmanager.html
  class PLoPBootManager < SimpleMenu
    TITLE = "PLoP Boot Manager"

    def initialize(ver)
      super("plop", ver)
    end

    def uri(top)
      "#{top.mirror(:plop_files)}/plpbt-#{@ver}.zip"
    end

    def main_after_download(download_file, parent, top)
      fu = top.fu

      fu.mkpath("tmp")
      fu.chdir("tmp") do
        top.xsystem("7z", "x", download_file)
      end
      fu.mv("tmp/plpbt-#{@ver}/plpbt.bin", "#{@dir}/plpbt")
      fu.rm_rf("tmp/plpbt-#{@ver}")
      fu.rmdir("tmp")

      cfg_puts <<-CFG
label #{@dir}
	menu label #{TITLE} #{@ver}
	kernel #{@dir}/plpbt
      CFG
    end
  end


  class FreedosBalder10 < SimpleMenu
    TITLE = "Balder 10 (FreeDOS 1.0)"

    def initialize
      super("freedos", "balder10")
    end

    def uri(top)
      top.mirror(:balder10_img)
    end

    def main_after_download(download_file, parent, top)
      fu = top.fu

      img = "#{@dir}/#{File.basename(download_file)}"
      fu.cp(download_file, img)

      cfg_puts <<-CFG
label #{@dir}
	menu label #{TITLE}
	kernel boot-screens/memdisk
	append initrd=#{img}
      CFG
    end
  end

  class GAG < SimpleMenu
    TITLE = "GAG (Graphical Boot Manager)"

    def initialize(ver)
      super("gag", ver)
    end

    def uri(top)
      sprintf(top.mirror(:gag_zip), @ver.tr(".", "_"))
    end

    def main_after_download(download_file, parent, top)
      fu = top.fu
      src_disk_dsk = "gag#{@ver}/disk.dsk"
      dst_disk_dsk = "#{@dir}/disk.dsk"

      fu.mkpath("tmp")
      fu.chdir("tmp") do
        top.xsystem("unzip", download_file, src_disk_dsk)
      end
      fu.mv("tmp/#{src_disk_dsk}", dst_disk_dsk)
      fu.rm_rf("tmp/#{File.dirname(src_disk_dsk)}")
      fu.rmdir("tmp")

      cfg_puts <<-CFG
label #{@dir}
	menu label #{TITLE} #{@ver}
	kernel boot-screens/memdisk
	append initrd=#{dst_disk_dsk}
      CFG
    end
  end


  # http://elm-chan.org/fsw/mbm/mbm.html
  class MBM < SimpleMenu
    TITLE = "MBM (Multiple Boot Manager)"

    def initialize(ver)
      super("mbm", ver)
    end

    def uri(top)
      top.mirror(:mbm_zip)
    end

    def main_after_download(download_file, parent, top)
      fu = top.fu

      fu.mkpath("tmp")
      fu.chdir("tmp") do
        top.xsystem("unzip", download_file, "BIN/MBM.144")
      end
      fu.mv("tmp/BIN", "#{@dir}/BIN")
      fu.rmdir("tmp")

      cfg_puts <<-CFG
label mbm
	menu label #{TITLE} #{@ver}
	kernel boot-screens/memdisk
	append initrd=#{@dir}/BIN/MBM.144
      CFG
    end
  end

  def setup_pxelinux(ver)
    tar_gz = "#{download_dir}/syslinux-#{ver}.tar.bz2"
    download(tar_gz, "#{mirror(:syslinux)}/syslinux-#{ver}.tar.bz2")
    fu.mkpath("tmp")
    fu.chdir("tmp") do
      xsystem("tar", "xf", tar_gz)
    end
    [
      "com32/menu/vesamenu.c32",
      "com32/modules/reboot.c32",
      #"com32/modules/chain.c32",
      "memdisk/memdisk",
      "modules/poweroff.com",
      "sample/syslinux_splash.jpg",
    ].each do |file|
      to_file = "#{boot_screens}/#{File.basename(file)}"
      fu.cp("tmp/syslinux-#{ver}/#{file}", to_file)
    end
    fu.rm_f("pxelinux.0")
    fu.cp("tmp/syslinux-#{ver}/core/pxelinux.0", "pxelinux.0")
    fu.mkpath("pxelinux")
    fu.rm_f("pxelinux.cfg")
    fu.ln_sf("pxelinux", "pxelinux.cfg")
    open("pxelinux/default", "w") do |f|
      f.write <<-CFG
include boot-screens/menu.cfg
include boot-screens/misc.cfg
default boot-screens/vesamenu.c32
prompt 0
timeout 0
      CFG
    end
    open("boot-screens/misc.cfg", "w") do |f|
      f.write <<-CFG
LABEL Poweroff
      KERNEL boot-screens/poweroff.com
LABEL Reboot
      KERNEL boot-screens/reboot.c32
LABEL 1st local disk
      localboot 0x80
LABEL 2nd local disk
      localboot 0x81
LABEL floppy disk
      localboot 0x00
      CFG
    end

    fu.rm_rf("tmp/syslinux-#{ver}")
    fu.rmdir("tmp")
  end

  def run(argv)
    top_menu = TopMenu.new("#{@boot_screens}/menu.cfg")
    syslinux_ver = "3.83"

    OptionParser.new do |opts|
      opts.on("--top-dir=DIR") do |v|
        set_top_dir(v)
      end

      opts.on("-v", "--[no-]verbose", "Run verbosely") do |v|
        set_verbose(v)
      end

      debian_suites = {
        "sid" => "sid (unstable)",
        "squeeze" => "squeeze (testing)",
        "lenny" => "lenny (stable)",
        "etch" => "etch (oldstable)",
        "etchnhalf" => "etch-and-a-half",
      }
      opts.on("--debian #{debian_suites.keys.join(',')}", Array, "Debian GNU/Linux Install") do |list|
        debian = Installer.new("debian", "Debian GNU/Linux")
        top_menu.push_sub_menu(debian)
        list.each do |suite|
          title = debian_suites[suite]
          case suite
          when "etchnhalf"
            [
              DebianAndAHalfInstaller.new(suite, title),
              DebianAndAHalfInstaller.new(suite, title, :arch => "amd64"),
              DebianAndAHalfInstaller.new(suite, title, :gtk => true),
              DebianAndAHalfInstaller.new(suite, title, :arch => "amd64", :gtk => true),
            ].each do |d_i|
              debian.push_sub_menu(d_i)
            end
          else
            [
              DebianInstaller.new(suite, title),
              DebianInstaller.new(suite, title, :arch => "amd64"),
              DebianInstaller.new(suite, title, :gtk => true),
              DebianInstaller.new(suite, title, :arch => "amd64", :gtk => true),
            ].each do |d_i|
              debian.push_sub_menu(d_i)
            end
          end
        end
      end

      ubuntu_suites = {
        "lucid" => "10.04 LTS Lucid Lynx",
        "karmic" => "9.10 Karmic Koara",
        "jaunty" => "9.04 Jaunty Jackalope",
        "intrepid" => "8.10 Intrepid Ibex",
        "hardy" => "8.04 LTS Hardy Heron",
        "dapper" => "6.06 LTS Dapper Drake",
      }
      opts.on("--ubuntu #{ubuntu_suites.keys.join(',')}", Array, "Ubuntu Linux Install") do |list|
        ubuntu = Installer.new("ubuntu", "Ubuntu Linux")
        top_menu.push_sub_menu(ubuntu)
        list.each do |suite|
          title = ubuntu_suites[suite]
          case suite
          when /\A[j]/
            [
              Ubuntu.new(suite, title),
              Ubuntu.new(suite, title, :arch => "amd64"),
              Ubuntu.new(suite, title, :gtk => true),
              Ubuntu.new(suite, title, :arch => "amd64", :gtk => true),
            ].each do |d_i|
              ubuntu.push_sub_menu(d_i)
            end
          else
            [
              Ubuntu.new(suite, title),
              Ubuntu.new(suite, title, :arch => "amd64"),
            ].each do |d_i|
              ubuntu.push_sub_menu(d_i)
            end
          end
        end
      end

      opts.on("--fedora 12,11,10,9", Array, "Fedora Install") do |list|
        fedora = Installer.new("fedora", "Fedora")
        top_menu.push_sub_menu(fedora)
        list.each do |ver|
          %w"i386 x86_64".each do |arch|
            options = {
              :distro => "fedora",
              :title => "Fedora",
              :ver => ver,
              :arch => arch,
              :template => "%s/%s/Fedora/%s/os/%s",
              # see http://fedoraproject.org/wiki/Anaconda/Options
              # http://docs.fedoraproject.org/install-guide/f11/en-US/html/ap-admin-options.html#sn-boot-options-installmethod
              #:append_template => "repo=%s/%s/Fedora/%s/os",
              :append_template => "method=%s/%s/Fedora/%s/os",
            }
            fedora.push_sub_menu(Anaconda.new(options))
          end
        end
      end

      opts.on("--centos 5.4,5.3,4.8,4.7", Array, "CentOS Install") do |list|
        centos = Installer.new("centos", "CentOS")
        top_menu.push_sub_menu(centos)
        list.each do |ver|
          %w"i386 x86_64".each do |arch|
            options = {
              :distro => "centos",
              :title => "CentOS",
              :ver => ver,
              :arch => arch,
              :template => "%s/%s/os/%s/%s",
              :append_template => "method=%s/%s/os/%s",
            }
            centos.push_sub_menu(Anaconda.new(options))
          end
        end
      end

      opts.on("--vine 5.0,4.2", Array, "Vine Linux Install") do |list|
        vine = Installer.new("vine", "Vine Linux")
        top_menu.push_sub_menu(vine)
        list.each do |ver|
          if 5 <= ver.to_i
            archs = %w"i386 x86_64"
          else
            archs = %w"i386"
          end
          archs.each do |arch|
            options = {
              :distro => "vine",
              :title => "Vine Linux",
              :ver => ver,
              :arch => arch,
              :template => "%s/Vine-%s/%s/%s",
            }
            vine.push_sub_menu(Anaconda.new(options))
          end
        end
      end

      opts.on("--mbm 0.39", MBM::TITLE) do |v|
        top_menu.push_sub_menu(MBM.new(v))
      end

      opts.on("--gag 4.10", GAG::TITLE) do |v|
        top_menu.push_sub_menu(GAG.new(v))
      end

      opts.on("--plop-boot-manager 5.0.4", PLoPBootManager::TITLE) do |v|
        top_menu.push_sub_menu(PLoPBootManager.new(v))
      end

      opts.on("--freedos-balder10", FreedosBalder10::TITLE) do |v|
        top_menu.push_sub_menu(FreedosBalder10.new)
      end

      opts.on("--ping 3.00.03", PING::TITLE) do |v|
        top_menu.push_sub_menu(PING.new(v))
      end

      opts.on("--syslinux VERSION", "Specify SYSLINUX version (default:#{syslinux_ver})") do |v|
        syslinux_ver = v
      end
    end.parse!(argv)

    setup_directories
    setup_pxelinux(syslinux_ver)
    top_menu.run(self, self)
  end
end

if __FILE__ == $0
  helper = PxeMultiBootHelper.new
  helper.run(ARGV)
end
