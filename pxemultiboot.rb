#!/usr/bin/ruby
# -*- coding: utf-8 -*-
=begin
= PXE Multi Boot environment builder
This program builds PXE multi boot environment.

== Requirements
* Ruby 1.8.x or later
* wget
* GNU tar (and gzip, bzip2)

Optional:
* unzip for some options
* bsdtar for --ubuntu-casper (ubuntu live iso)

== Usage
== build tftpboot
* ruby pxemultiboot.rb --help
* ruby pxemultiboot.rb --debian lenny,etch,etchnhalf,squeeze,sid --ubuntu karmic,hardy,jaunty,intrepid,dapper,lucid --fedora 12,11,10,9 --centos 5.4,5.3,4.8,4.7 --vine 5.0,4.2 --memtest 4.00 --mbm 0.39 --plop-boot-manager 5.0.4 --freedos-balder10 --gag 4.10 --ping 3.00.03 --grub4dos 0.4.4

== PXE boot
* put tftpboot into tftpd's directory
* setup dhcpd PXE bootable
* boot some machine using PXE

== License
The MIT License

Copyright (C) 2009, 2010 Kazuhiro NISHIYAMA

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

      :memtest => "http://www.memtest.org/download/%s/memtest86+-%s.zip",

      :ping_release => "http://ping.windowsdream.com/ping/Releases",
      :plop_files => "http://download.plop.at/files/bootmngr",
      :balder10_img => "http://www.finnix.org/files/balder10.img",
      :mbm_zip => "http://my.vector.co.jp/servlet/System.FileDownload/download/http/0/35596/pack/dos/util/boot/mbm039.zip",
      :gag_zip => "http://downloads.sourceforge.net/gag/gag%s.zip",
      :grub4dos => "http://download.gna.org/grub4dos/grub4dos-%s.zip",

      # http://openlab.ring.gr.jp/oscircular/inetboot/index.html
      :inetboot => "http://ring.aist.go.jp/archives/linux/oscircular/iso",
    }
  end

  def mirror(target)
    @mirror[target] or raise "unknown target: #{target}"
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

  class SubMenu < Menu
    def initialize(name, title)
      @name = name
      @title = title
      super("boot-screens/#{@name}.cfg")
    end

    def cfg_prologue
      <<-CFG
menu begin #{@title}
	menu title #{@title}
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

  class DebianLive < Menu
    def initialize(binary_net_tar, title)
      @binary_net_tar = File.expand_path(binary_net_tar)
      @title = title
      super("boot-screens/debian-live-#{base}.cfg")
    end

    def binary_net_tar
      @binary_net_tar
    end

    def base
      @base ||= File.basename(binary_net_tar).sub(/\..*\z/, '')
    end

    def extract_dir
      "debian-live"
    end

    def live_dir
      "debian-live/#{base}"
    end

    def arch
      "i386"
    end

    def main(parent, top)
      fu = top.fu

      fu.mkpath("tmp")
      fu.chdir("tmp") do
        top.xsystem("tar", "xf", binary_net_tar, "tftpboot/#{extract_dir}/#{arch}")
      end

      fu.rm_rf(live_dir)
      fu.mkpath(live_dir)
      fu.mv("tmp/tftpboot/#{extract_dir}/#{arch}", live_dir)
      fu.rmdir("tmp/tftpboot/#{extract_dir}")
      fu.rmdir("tmp/tftpboot")
      fu.rmdir("tmp")

      menu_cfg = "#{live_dir}/#{arch}/boot-screens/menu.cfg"
      proc_cfg_file = proc do |cfg_filename|
        File.foreach(cfg_filename) do |line|
          line.gsub!(extract_dir) { live_dir }
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

      kernel = "#{live_dir}/#{arch}/boot-screens/vesamenu.c32"
      unless File.exist?(kernel)
        kernel = "boot-screens/vesamenu.c32"
      end
      parent.cfg_puts <<-CFG
label debian-live-#{base}
	menu label #{@title}
	kernel #{kernel}
	append boot-screens/debian-live-#{base}.cfg
      CFG
    end
  end # DebianLive

  class UbuntuCasper < Menu
    def initialize(ubuntu_iso, title, casper_options)
      @ubuntu_iso = File.expand_path(ubuntu_iso)
      @title = title
      @casper_options = casper_options
      super("boot-screens/ubuntu-casper-#{base}.cfg")
    end

    def ubuntu_iso
      @ubuntu_iso
    end

    def casper_options
      @casper_options
    end

    def base
      @base ||= File.basename(ubuntu_iso).sub(/\.iso\z/, '')
    end

    def live_dir
      "ubuntu-casper/#{base}"
    end

    def main(parent, top)
      fu = top.fu

      fu.mkpath("tmp/casper")
      fu.chdir("tmp") do
        files = [
          "casper/initrd.gz",
          "casper/initrd.lz",
          "casper/vmlinuz",
          "isolinux",
          "preseed",
        ]
        top.xsystem("bsdtar", "-xf", ubuntu_iso, *files)
        fu.chmod(0755, ["casper", "isolinux", "preseed"])
        fu.chmod(0644, Dir.glob("{casper,isolinux,preseed}/*"))
      end

      fu.rm_rf(live_dir)
      fu.mkpath("#{live_dir}/casper")
      [
        "initrd.gz",
        "initrd.lz",
        "vmlinuz",
      ].each do |filename|
        if File.exist?("tmp/casper/#{filename}")
          fu.mv("tmp/casper/#{filename}", "#{live_dir}/casper/#{filename}")
        end
      end
      fu.mv("tmp/isolinux", live_dir)
      fu.mv("tmp/preseed", live_dir)
      fu.rmdir("tmp/casper")
      fu.rmdir("tmp")

      isolinux_cfg = "#{live_dir}/isolinux/isolinux.cfg"
      proc_cfg_file = proc do |cfg_filename|
        File.foreach(cfg_filename) do |line|
          if /\s*include (\S+)/ =~ line
            if File.exist?("#{live_dir}/isolinux/#{$1}")
              cfg_puts '#^^^ ' + line
              proc_cfg_file.call("#{live_dir}/isolinux/#{$1}")
              cfg_puts '#$$$ ' + line
            else
              cfg_puts '#### ' + line
            end
          else
            line.gsub!(/(\S+\s+)(?=(\S+))/) do
              match, filename = $~.captures
              if File.exist?("#{live_dir}/isolinux/#{filename}")
                "#{match}/#{live_dir}/isolinux/"
              else
                match
              end
            end
            line.sub!(/kernel\s+|initrd=/) do
              "#{$&}#{live_dir}"
            end
            line.sub!(/boot=casper/) do
              "#{$&} #{casper_options}"
            end
            line.sub!(/^timeout/i) do
              "\##{$&}"
            end
            cfg_puts line
          end
        end
      end
      proc_cfg_file.call(isolinux_cfg)

      kernel = "#{live_dir}/isolinux/vesamenu.c32"
      unless File.exist?(kernel)
        kernel = "boot-screens/vesamenu.c32"
      end
      parent.cfg_puts <<-CFG
label ubuntu-casper-#{base}
	menu label #{@title}
	kernel #{kernel}
	append boot-screens/ubuntu-casper-#{base}.cfg
      CFG
    end
  end # UbuntuCasper

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
      @name ||= name
      @ver ||= ver
      @dir ||= "#{@name}-#{@ver}"
      super("boot-screens/#{@dir}.cfg")
    end

    def title
      "#{self.class::TITLE} #{@ver}"
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

  class FloppyImage < SimpleMenu
    def main_after_download(download_file, parent, top)
      img = install_img(download_file, parent, top)

      cfg_puts <<-CFG
label #{@dir}
	menu label #{title}
	kernel boot-screens/memdisk
	append initrd=#{img}
      CFG
    end

    def install_img(download_file, parent, top)
      img = "#{@dir}/#{File.basename(download_file)}"
      top.fu.cp(download_file, img)
      return img
    end
  end

  class KernelImage < FloppyImage
    def main_after_download(download_file, parent, top)
      img = install_img(download_file, parent, top)

      cfg_puts <<-CFG
label #{@dir}
	menu label #{title}
	kernel #{img}
      CFG
    end
  end

  class ImageFile < FloppyImage
    def initialize(title, uri)
      @title = title
      @uri = uri
      @dir = "image"
      super("image", "dummy_ver")
    end

    def title
      @title
    end

    def uri(top)
      @uri
    end
  end

  class FreedosBalder10 < FloppyImage
    TITLE = "Balder 10 (FreeDOS 1.0)"

    # title without ver
    def title
      TITLE
    end

    def initialize
      super("freedos", "balder10")
    end

    def uri(top)
      top.mirror(:balder10_img)
    end
  end

  class GAG < FloppyImage
    TITLE = "GAG (Graphical Boot Manager)"

    def initialize(ver)
      super("gag", ver)
    end

    def uri(top)
      sprintf(top.mirror(:gag_zip), @ver.tr(".", "_"))
    end

    def install_img(download_file, parent, top)
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

      return dst_disk_dsk
    end
  end

  # http://elm-chan.org/fsw/mbm/mbm.html
  class MBM < FloppyImage
    TITLE = "MBM (Multiple Boot Manager)"

    def initialize(ver)
      super("mbm", ver)
    end

    def uri(top)
      top.mirror(:mbm_zip)
    end

    def install_img(download_file, parent, top)
      fu = top.fu

      fu.mkpath("tmp")
      fu.chdir("tmp") do
        top.xsystem("unzip", download_file, "BIN/MBM.144")
      end
      fu.mv("tmp/BIN/MBM.144", @dir)
      fu.rmdir("tmp/BIN")
      fu.rmdir("tmp")

      return "#{@dir}/MBM.144"
    end
  end

  # http://www.plop.at/en/bootmanager.html
  class PLoPBootManager < KernelImage
    TITLE = "PLoP Boot Manager"

    def initialize(ver)
      super("plop", ver)
    end

    def uri(top)
      "#{top.mirror(:plop_files)}/plpbt-#{@ver}.zip"
    end

    def install_img(download_file, parent, top)
      fu = top.fu

      fu.mkpath("tmp")
      fu.chdir("tmp") do
        top.xsystem("unzip", download_file)
      end

      plpbt = "#{@dir}/plpbt"
      fu.mv("tmp/plpbt-#{@ver}/plpbt.bin", plpbt)
      fu.rm_rf("tmp/plpbt-#{@ver}")
      fu.rmdir("tmp")

      return plpbt
    end
  end

  class Memtest < KernelImage
    TITLE = "Memtest86+"

    def initialize(ver)
      super("memtest", ver)
    end

    def uri(top)
      sprintf(top.mirror(:memtest), @ver, @ver)
    end

    def install_img(download_file, parent, top)
      fu = top.fu

      fu.mkpath("tmp")
      fu.chdir("tmp") do
        top.xsystem("unzip", download_file, "memtest86+-#{@ver}.bin")
      end

      memtest_bin = "#{@dir}/memtest86+"
      fu.mv("tmp/memtest86+-#{@ver}.bin", memtest_bin)
      fu.rmdir("tmp")

      return memtest_bin
    end
  end

  class Grub4Dos < SimpleMenu
    TITLE = "GRUB for DOS"

    def initialize(ver)
      super("grub4dos", ver)
    end

    def uri(top)
      sprintf(top.mirror(:grub4dos), @ver)
    end

    def main_after_download(download_file, parent, top)
      fu = top.fu

      grub_exe = "#{@dir}/grub.exe"
      files = [grub_exe, "#{@dir}/menu.lst"]
      fu.mkpath("tmp")
      fu.chdir("tmp") do
        top.xsystem("unzip", download_file, *files)
      end
      files.each do |file|
        fu.mv("tmp/#{file}", file)
      end
      fu.rmdir("tmp/#{@dir}")
      fu.rmdir("tmp")

      cfg_puts <<-CFG
label #{@dir}
	menu label #{title}
	kernel #{grub_exe}
	append keeppxe --config-file="pxe basedir /;configfile (pd)/#{@dir}/menu.lst"
      CFG
    end
  end

  # http://rom-o-matic.net/
  class GPXE < Menu
    TITLE = "gPXE"

    def initialize(image_file)
      @image_file = image_file
      @basename = File.basename(image_file)
      if /[0-9.+]+/ =~ @basename
        @dir = "gpxe-#{$&}"
      else
        @dir = "gpxe"
      end
      super("boot-screens/gpxe-#{@basename}.cfg")
    end

    def main(parent, top)
      fu = top.fu

      basename = File.basename(@image_file)
      fu.mkpath(@dir)
      fu.cp(@image_file, @dir)

      cfg_puts <<-CFG
label #{basename}
	menu label #{TITLE} (#{basename})
      CFG
      case basename
      when /\.sdsk\z/
        cfg_puts <<-CFG
	kernel boot-screens/memdisk
	append initrd=#{@dir}/#{basename}
        CFG
      when /\.lkrn\z/
        cfg_puts <<-CFG
	kernel #{@dir}/#{basename}
        CFG
      else
        raise "unknown gPXE format: #{basename}"
      end

      parent.menu_include @menu_cfg
    end

    def cfg_prologue
      nil
    end
  end

  # http://openlab.ring.gr.jp/oscircular/inetboot/index.html
  class InetBoot < Menu
    def initialize(ver, label, title, append)
      @ver = ver
      @dir = "inetboot-#{@ver}"
      @label = label
      @title = title
      @append = append
      super("boot-screens/inetboot-#{@label}.cfg")
    end

    def main(parent, top)
      ensure_inetboot(top)

      unless /netdir=(\S+)/ =~ @append
        raise "netdir option not found in append: #{@append}"
      end
      uri = $1
      unless top.xsystem("wget", "--spider", uri)
        raise "not found: #{uri}"
      end

      cfg_puts <<-CFG
label #{@label}
	menu label #{@title}
	kernel /#{@dir}/linux
	append initrd=/#{@dir}/minirt.gz #{@append}
      CFG

      parent.menu_include @menu_cfg
    end

    def cfg_prologue
      nil
    end

    def ensure_inetboot(top)
      return if File.directory?(@dir)
      fu = top.fu
      download_dir = "#{top.download_dir}/#{@dir}"
      fu.mkpath(download_dir)
      files = %w"linux minirt.gz"
      files.each do |file|
        uri = "#{top.mirror(:inetboot)}/#{@dir}/#{file}"
        top.download("#{download_dir}/#{file}", uri)
      end
      fu.mkpath(@dir)
      files.each do |file|
        fu.cp("#{download_dir}/#{file}", "#{@dir}/#{file}")
      end
    end
  end # InetBoot

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
menu begin SYSLINUX
  menu title Syslinux
    LABEL mainmenu
      menu label ^Back..
      menu exit

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

menu end
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
      debian_title = "Debian GNU/Linux Install"
      opts.on("--debian #{debian_suites.keys.join(',')}", Array, debian_title) do |list|
        debian = SubMenu.new("debian", debian_title)
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
          when "sid", "squeeze"
            # 2009-12-30:
            # sid/main/installer-{i386,amd64}/current/images/netboot/gtk/
            # (current -> 20091215)
            # missing now.
            [
              DebianInstaller.new(suite, title),
              DebianInstaller.new(suite, title, :arch => "amd64"),
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

      debian_live_title = "Debian Live"
      opts.on("--debian-live 'path/to/binary-net.tar.gz;Debian Live SubTitle'", /\A[^;]+;.+\Z/, debian_live_title) do |match|
        path, title = match.split(/;/, 2)
        debian_live = DebianLive.new(path, title)
        top_menu.push_sub_menu(debian_live)
      end

      ubuntu_casper_title = "Ubuntu Casper"
      opts.on("--ubuntu-casper 'path/to/ubuntu.iso;Ubuntu Casper SubTitle;netboot=nfs nfs-server-ip:path/to/live'", /\A[^;]+;[^;]+;.+\Z/, ubuntu_casper_title) do |match|
        path, title, casper_options = match.split(/;/, 3)
        ubuntu_casper = UbuntuCasper.new(path, title, casper_options)
        top_menu.push_sub_menu(ubuntu_casper)
      end

      ubuntu_suites = {
        "lucid" => "10.04 LTS Lucid Lynx",
        "karmic" => "9.10 Karmic Koara",
        "jaunty" => "9.04 Jaunty Jackalope",
        "intrepid" => "8.10 Intrepid Ibex",
        "hardy" => "8.04 LTS Hardy Heron",
        "dapper" => "6.06 LTS Dapper Drake",
      }
      ubuntu_title = "Ubuntu Linux Install"
      opts.on("--ubuntu #{ubuntu_suites.keys.join(',')}", Array, ubuntu_title) do |list|
        ubuntu = SubMenu.new("ubuntu", ubuntu_title)
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

      fedora_title = "Fedora Install"
      opts.on("--fedora 12,11,10,9", Array, fedora_title) do |list|
        fedora = SubMenu.new("fedora", fedora_title)
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

      centos_title = "CentOS Install"
      opts.on("--centos 5.4,5.3,4.8,4.7", Array, centos_title) do |list|
        centos = SubMenu.new("centos", centos_title)
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

      vine_title = "Vine Linux Install"
      opts.on("--vine 5.0,4.2", Array, vine_title) do |list|
        vine = SubMenu.new("vine", vine_title)
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

      opts.on("--memtest 4.00", Memtest::TITLE) do |v|
        top_menu.push_sub_menu(Memtest.new(v))
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

      opts.on("--grub4dos 0.4.4", Grub4Dos::TITLE) do |v|
        top_menu.push_sub_menu(Grub4Dos.new(v))
      end

      opts.on("--gpxe image.lkrn", "gPXE image file download from http://rom-o-matic.net/") do |v|
        image_file = File.expand_path(v)
        top_menu.push_sub_menu(GPXE.new(image_file))
      end

      opts.on("--image-file 'Image Title;uri-of-image-file'", /\A[^;]+;.+\Z/, "Disk Image File") do |match|
        title, uri = match.split(/;/, 2)
        top_menu.push_sub_menu(ImageFile.new(title, uri))
      end

      inetboot_sub_menu = nil
      inetboot_ver = "20080925"
      opts.on("--inetboot label,title,append", Array, "InetBoot") do |label, title, append|
        unless inetboot_sub_menu
          inetboot_sub_menu = SubMenu.new("inetboot", "InetBoot #{inetboot_ver}")
          top_menu.push_sub_menu(inetboot_sub_menu)
        end
        inetboot = InetBoot.new(inetboot_ver, label, title, append)
        inetboot_sub_menu.push_sub_menu(inetboot)
      end

      opts.on("--inetboot-examples", "Show InetBoot option examples and exit") do
        inetboot_base_uri = "http://192.168.x.y/iso"
        inetboot_example_show = proc {|o|
          puts "--inetboot=#{o[:label]},#{o[:title]},#{o[:append]}"
        }
        inetboot_example_show.call({
            :label => "knoppix601",
            :title => "KNOPPIX 6.0.1",
            :append => "netdir=#{inetboot_base_uri}/knoppix_v6.0.1CD_20090208-20090225_opt.iso type=knoppix ramdisk_size=100000 lang=ja screen=1024x768",
          })
        inetboot_example_show.call({
            :label => "knoppix531",
            :title => "KNOPPIX 5.3.1 lang=ja",
            :append => "netdir=#{inetboot_base_uri}/knoppix_v5.3.1CD_20080326-20080520.iso type=knoppix ramdisk_size=100000 lang=ja screen=1024x768",
          })
        inetboot_example_show.call({
      :label => "knoppix531_vesa",
      :title => "KNOPPIX 5.3.1 lang=ja vesa",
      :append => "netdir=#{inetboot_base_uri}/knoppix_v5.3.1CD_20080326-20080520.iso type=knoppix ramdisk_size=100000 lang=ja xmodule=vesa screen=1024x768",
          })
        inetboot_example_show.call({
            :label => "knoppix-511",
            :title => "KNOPPIX 5.1.1 lang=ja lang=ja.utf8",
            :append => "netdir=#{inetboot_base_uri}/knoppix_v5.1.1CD_20070104-20070122+IPAFont_AC20070123.iso type=knoppix ramdisk_size=100000 lang=ja.utf8 vga=normal screen=1024x768",
          })
        inetboot_example_show.call({
            :label => "knoppix-511-vesa",
            :title => "KNOPPIX 5.1.1 lang=ja lang=ja.utf8 vesa",
            :append => "netdir=#{inetboot_base_uri}/knoppix_v5.1.1CD_20070104-20070122+IPAFont_AC20070123.iso type=knoppix ramdisk_size=100000 lang=ja.utf8 vga=normal xmodule=vesa screen=1024x768",
          })
        inetboot_example_show.call({
            :label => "fedora9",
            :title => "Fedora 9 Desktop Live",
            :append => "netdir=#{inetboot_base_uri}/Fedora-9-i686-Live.iso type=fedora",
          })
        inetboot_example_show.call({
            :label => "ubuntu804",
            :title => "Ubuntu (ja) 8.04.2 (casper)",
            :append => "netdir=#{inetboot_base_uri}/ubuntu-ja-8.04.2-desktop-i386.iso type=casper",
          })
        inetboot_example_show.call({
            :label => "ecolinux804",
            :title => "Ecolinux 8.04.8 (casper)",
            :append => "netdir=#{inetboot_base_uri}/ecolinux-8.04.8.iso type=casper",
          })
        exit
      end

      opts.on("-f", "--arg-file FILE", "read arguments from file") do |v|
        args = []
        File.foreach(v) do |s|
          next if /\A\s*\#/ =~ s
          args.push s.chomp
        end
        argv.unshift(*args)
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
