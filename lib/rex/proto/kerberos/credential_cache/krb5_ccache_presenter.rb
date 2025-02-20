# frozen_string_literal: true

require 'base64'
require 'rex/proto/kerberos/pac/krb5_pac'

module Rex::Proto::Kerberos::CredentialCache
  class Krb5CcachePresenter

    ADDRESS_TYPE_MAP = {
      Rex::Proto::Kerberos::Model::AddressType::IPV4 => 'IPV4',
      Rex::Proto::Kerberos::Model::AddressType::DIRECTIONAL => 'DIRECTIONAL',
      Rex::Proto::Kerberos::Model::AddressType::CHAOS_NET => 'CHAOS NET',
      Rex::Proto::Kerberos::Model::AddressType::XNS => 'XNS',
      Rex::Proto::Kerberos::Model::AddressType::ISO => 'ISO',
      Rex::Proto::Kerberos::Model::AddressType::DECNET_PHASE_IV => 'DECNET PHASE IV',
      Rex::Proto::Kerberos::Model::AddressType::APPLE_TALK_DDP => 'APPLE TALK DDP',
      Rex::Proto::Kerberos::Model::AddressType::NET_BIOS => 'NET BIOS',
      Rex::Proto::Kerberos::Model::AddressType::IPV6 => 'IPV6'
    }.freeze
    private_constant :ADDRESS_TYPE_MAP

    AD_TYPE_MAP = {
      Rex::Proto::Kerberos::Model::AuthorizationDataType::AD_IF_RELEVANT => 'IF_RELEVANT',
      Rex::Proto::Kerberos::Model::AuthorizationDataType::KDC_ISSUED => 'KDC_ISSUED',
      Rex::Proto::Kerberos::Model::AuthorizationDataType::AND_OR => 'AND_OR',
      Rex::Proto::Kerberos::Model::AuthorizationDataType::MANDATORY_FOR_KDC => 'MANDATORY_FOR_KDC',
      Rex::Proto::Kerberos::Model::AuthorizationDataType::INITIAL_VERIFIED_CAS => 'INITIAL_VERIFIED_CAS',
      Rex::Proto::Kerberos::Model::AuthorizationDataType::OSF_DCE => 'OSF_DCE',
      Rex::Proto::Kerberos::Model::AuthorizationDataType::SESAME => 'SESAME'
    }.freeze
    private_constant :AD_TYPE_MAP

    # @param [Rex::Proto::Kerberos::CredentialCache::Krb5Ccache] ccache
    def initialize(ccache)
      @ccache = ccache
    end

    # @param [String,nil] key Decryption key for the encrypted part
    # @return [String] A human readable representation of a ccache object
    def present(key: nil)
      output = []
      output << "Primary Principal: #{ccache.default_principal}"
      output << "Ccache version: #{ccache.version}"
      output << ''
      output << "Creds: #{ccache.credentials.length}"
      output << ccache.credentials.map.with_index do |cred, index|
        "Credential[#{index}]:\n#{present_cred(cred, key: key).indent(2)}".indent(2)
      end.join("\n")
      output.join("\n")
    end

    # @return [Rex::Proto::Kerberos::CredentialCache::Krb5Ccache]
    attr_reader :ccache

    # @param [Rex::Proto::Kerberos::CredentialCache::Krb5CcacheCredential] cred
    # @param [String,nil] key Decryption key for the encrypted part
    # @return [String] A human readable representation of a ccache credential
    def present_cred(cred, key: nil)
      output = []
      output << "Server: #{cred.server}"
      output << "Client: #{cred.client}"
      output << "Ticket etype: #{cred.keyblock.enctype} (#{Rex::Proto::Kerberos::Crypto::Encryption.const_name(cred.keyblock.enctype)})"
      output << "Key: #{cred.keyblock.data.unpack1('H*')}"
      output << "Subkey: #{cred.is_skey == 1}"
      output << "Ticket Length: #{cred.ticket.length}"
      output << "Ticket Flags: 0x#{cred.ticket_flags.to_i.to_s(16).rjust(8, '0')} (#{Rex::Proto::Kerberos::Model::KdcOptionFlags.new(cred.ticket_flags.to_i).enabled_flag_names.join(', ')})"
      ticket = Rex::Proto::Kerberos::Model::Ticket.decode(cred.ticket.value)

      output << "Addresses: #{cred.address_count}"

      unless cred.address_count == 0
        output << cred.addresses.map do |address|
          "#{ADDRESS_TYPE_MAP.fetch(address.addrtype, address.addrtype)}: #{address.data}".indent(2)
        end.join("\n")
      end

      output << "Authdatas: #{cred.authdata_count}"
      unless cred.authdata_count == 0
        output << cred.authdatas.map do |authdata|
          "#{AD_TYPE_MAP.fetch(authdata.adtype, authdata.adtype)}: #{authdata.data}".indent(2)
        end.join("\n")
      end

      output << 'Times:'
      output << "Auth time: #{cred.authtime}".indent(2)
      output << "Start time: #{cred.starttime}".indent(2)
      output << "End time: #{cred.endtime}".indent(2)
      output << "Renew Till: #{cred.renew_till}".indent(2)

      output << 'Ticket:'
      output << "Ticket Version Number: #{ticket.tkt_vno}".indent(2)
      output << "Realm: #{ticket.realm}".indent(2)
      output << "Server Name: #{ticket.sname}".indent(2)
      output << 'Encrypted Ticket Part:'.indent(2)
      output << "Ticket etype: #{ticket.enc_part.etype} (#{Rex::Proto::Kerberos::Crypto::Encryption.const_name(ticket.enc_part.etype)})".indent(4)
      output << "Key Version Number: #{ticket.enc_part.kvno}".indent(4)

      if key.blank?
        output << 'Cipher:'.indent(4)
        output << Base64.strict_encode64(ticket.enc_part.cipher).indent(6)
      else
        output << "Decrypted (with key: #{key.bytes.map { |x| "#{x.to_s(16).rjust(2, '0')}" }.join}):".indent(4)
        output << present_encrypted_ticket_part(ticket, key).indent(6)
      end

      output.join("\n")
    end

    # @param [Rex::Proto::Kerberos::Pac::Krb5LogonInfo] logon_info
    # @return [String] A human readable representation of a Logon Information
    def present_logon_info(logon_info)
      validation_info = logon_info.data
      output = []
      output << 'Validation Info:'

      output << "Logon Time: #{present_time(validation_info.logon_time)}".indent(2)
      output << "Logoff Time: #{present_time(validation_info.logoff_time)}".indent(2)
      output << "Kick Off Time: #{present_time(validation_info.kick_off_time)}".indent(2)
      output << "Password Last Set: #{present_time(validation_info.password_last_set)}".indent(2)
      output << "Password Can Change: #{present_time(validation_info.password_can_change)}".indent(2)
      output << "Password Must Change: #{present_time(validation_info.password_must_change)}".indent(2)

      output << "Logon Count: #{validation_info.logon_count}".indent(2)
      output << "Bad Password Count: #{validation_info.bad_password_count}".indent(2)
      output << "User ID: #{validation_info.user_id}".indent(2)
      output << "Primary Group ID: #{validation_info.primary_group_id}".indent(2)
      output << "User Flags: #{validation_info.user_flags}".indent(2)
      output << "User Session Key: #{present_user_session_key(validation_info.user_session_key)}".indent(2)
      output << "User Account Control: #{validation_info.user_account_control}".indent(2)
      output << "Sub Auth Status: #{validation_info.sub_auth_status}".indent(2)

      output << "Last Successful Interactive Logon: #{present_time(validation_info.last_successful_i_logon)}".indent(2)
      output << "Last Failed Interactive Logon: #{present_time(validation_info.last_failed_i_logon)}".indent(2)
      output << "Failed Interactive Logon Count: #{validation_info.failed_i_logon_count}".indent(2)

      output << "SID Count: #{validation_info.sid_count}".indent(2)
      output << "Resource Group Count: #{validation_info.resource_group_count}".indent(2)

      output << "Group Count: #{validation_info.group_count}".indent(2)
      output << 'Group IDs:'.indent(2)
      output << validation_info.group_memberships.map { |group| "Relative ID: #{group.relative_id}, Attributes: #{group.attributes}".indent(4) }

      output << "Logon Domain ID: #{validation_info.logon_domain_id}".indent(2)

      output << "Effective Name: #{present_rpc_unicode_string(validation_info.effective_name)}".indent(2)
      output << "Full Name: #{present_rpc_unicode_string(validation_info.full_name)}".indent(2)
      output << "Logon Script: #{present_rpc_unicode_string(validation_info.logon_script)}".indent(2)
      output << "Profile Path: #{present_rpc_unicode_string(validation_info.profile_path)}".indent(2)
      output << "Home Directory: #{present_rpc_unicode_string(validation_info.home_directory)}".indent(2)
      output << "Home Directory Drive: #{present_rpc_unicode_string(validation_info.home_directory_drive)}".indent(2)
      output << "Logon Server: #{present_rpc_unicode_string(validation_info.logon_server)}".indent(2)
      output << "Logon Domain Name: #{present_rpc_unicode_string(validation_info.logon_domain_name)}".indent(2)

      output.join("\n")
    end

    # @param [Rex::Proto::Kerberos::Pac::Krb5ClientInfo] client_info
    # @return [String] A human readable representation of a Client Info
    def present_client_info(client_info)
      output = []
      output << 'Client Info:'
      output << "Name: '#{client_info.name.encode('utf-8')}'".indent(2)
      output << "Client ID: #{present_time(client_info.client_id)}".indent(2)
      output.join("\n")
    end

    # @param [Rex::Proto::Kerberos::Pac::Krb5PacServerChecksum] server_checksum
    # @return [String] A human readable representation of a Server Checksum
    def present_server_checksum(server_checksum)
      sig = server_checksum.signature.bytes.map { |x| "#{x.to_s(16).rjust(2, '0')}" }.join
      "Pac Server Checksum:\n" +
        "Signature: #{sig}".indent(2)
    end

    # @param [Rex::Proto::Kerberos::Pac::Krb5PacPrivServerChecksum] priv_server_checksum
    # @return [String] A human readable representation of a Privilege Server Checksum
    def present_priv_server_checksum(priv_server_checksum)
      sig = priv_server_checksum.signature.bytes.map { |x| "#{x.to_s(16).rjust(2, '0')}" }.join
      "Pac Privilege Server Checksum:\n" +
        "Signature: #{sig}".indent(2)
    end

    # @param [Rex::Proto::Kerberos::Pac::Krb5UpnDnsInfo] upn_and_dns_info
    # @return [String] A human readable representation of a UPN and DNS information element
    def present_upn_and_dns_information(upn_and_dns_info)
      output = []
      output << 'UPN and DNS Information:'
      output << "UPN: #{upn_and_dns_info.upn.encode('utf-8')}".indent(2)
      output << "DNS Domain Name: #{upn_and_dns_info.dns_domain_name.encode('utf-8')}".indent(2)

      output << "Flags: #{upn_and_dns_info.flags}".indent(2)

      if upn_and_dns_info.has_s_flag?
        output << "SAM Name: #{upn_and_dns_info.sam_name.encode('utf-8')}".indent(2)
        output << "SID: #{upn_and_dns_info.sid}".indent(2)
      end
      output.join("\n")
    end

    # @param [Rex::Proto::Kerberos::Pac::Krb5PacInfoBuffer] info_buffer
    # @return [String] A human readable representation of a Pac Info Buffer
    def present_pac_info_buffer(info_buffer)
      ul_type = info_buffer.ul_type.to_i
      pac_element = info_buffer.buffer.pac_element
      case ul_type
      when Rex::Proto::Kerberos::Pac::Krb5PacElementType::LOGON_INFORMATION
        present_logon_info(pac_element)
      when Rex::Proto::Kerberos::Pac::Krb5PacElementType::CLIENT_INFORMATION
        present_client_info(pac_element)
      when Rex::Proto::Kerberos::Pac::Krb5PacElementType::SERVER_CHECKSUM
        present_server_checksum(pac_element)
      when Rex::Proto::Kerberos::Pac::Krb5PacElementType::PRIVILEGE_SERVER_CHECKSUM
        present_priv_server_checksum(pac_element)
      when Rex::Proto::Kerberos::Pac::Krb5PacElementType::USER_PRINCIPAL_NAME_AND_DNS_INFORMATION
        present_upn_and_dns_information(pac_element)
      else
        ul_type_name = Rex::Proto::Kerberos::Pac::Krb5PacElementType.const_name(ul_type)
        ul_type_name = ul_type_name.gsub('_', ' ').capitalize if ul_type_name
        "#{ul_type_name || "Unknown ul type #{ul_type}"}:\n" +
          "#{info_buffer.to_s}".indent(2)
      end
    end

    # @param [Rex::Proto::Kerberos::Model::Ticket] ticket
    # @param [String] key Decryption key for the encrypted part
    # @return [String] A human readable representation of an Encrypted Ticket Part
    def present_encrypted_ticket_part(ticket, key)
      enc_class = Rex::Proto::Kerberos::Crypto::Encryption.from_etype(ticket.enc_part.etype)

      decrypted_part = enc_class.decrypt(ticket.enc_part.cipher, key, 2)
      ticket_enc_part = Rex::Proto::Kerberos::Model::TicketEncPart.decode(decrypted_part)
      output = []
      output << 'Times:'
      output << "Auth time: #{ticket_enc_part.authtime}".indent(2)
      output << "Start time: #{ticket_enc_part.starttime}".indent(2)
      output << "End time: #{ticket_enc_part.endtime}".indent(2)
      output << "Renew Till: #{ticket_enc_part.renew_till}".indent(2)

      output << "Client Addresses: #{ticket_enc_part.caddr.to_a.length}"
      unless ticket_enc_part.caddr.to_a.empty?
        output << ticket_enc_part.caddr.to_a.map do |address|
          "#{ADDRESS_TYPE_MAP.fetch(address.type, address.type)}: #{address.address}".indent(2)
        end.join("\n")
      end

      output << "Transited: tr_type: #{ticket_enc_part.transited.tr_type}, Contents: #{ticket_enc_part.transited.contents.inspect}"

      output << "Client Name: '#{ticket_enc_part.cname}'"
      output << "Client Realm: '#{ticket_enc_part.crealm}'"
      output << "Ticket etype: #{ticket_enc_part.key.type} (#{Rex::Proto::Kerberos::Crypto::Encryption.const_name(ticket_enc_part.key.type)})"
      output << "Encryption Key: #{ticket_enc_part.key.value.unpack1('H*')}"
      output << "Flags: 0x#{ticket_enc_part.flags.to_i.to_s(16).rjust(8, '0')} (#{ticket_enc_part.flags.enabled_flag_names.join(', ')})"

      auth_data_data = ticket_enc_part.authorization_data.elements.first[:data]

      pac_string = OpenSSL::ASN1.decode(auth_data_data).value[0].value[1].value[0].value

      pac = Rex::Proto::Kerberos::Pac::Krb5Pac.read(pac_string)
      output << 'PAC:'
      output << pac.pac_info_buffers.map do |pac_info_buffer|
        present_pac_info_buffer(pac_info_buffer).indent(2)
      end
      output.join("\n")
    end

    # @param [RubySMB::Dcerpc::RpcUnicodeString] rpc_unicode_string
    # @return [String (frozen)]
    def present_rpc_unicode_string(rpc_unicode_string)
      if rpc_unicode_string.buffer.is_null_ptr?
        'nil'
      else
        "'#{rpc_unicode_string.buffer.encode('UTF-8')}'"
      end
    end

    # @param [Rex::Proto::Kerberos::Pac::UserSessionKey] user_session_key
    # @return [String] A human readable representation of a User Session Key
    def present_user_session_key(user_session_key)
      user_session_key.session_key.flat_map(&:data).map { |x| "#{x.to_i.to_s(16).rjust(2, '0')}" }.join
    end

    # @param [RubySMB::Dcerpc::Ndr::NdrFileTime] time
    # @return [String] A human readable representation of the time
    def present_time(time)
      if time.get == Rex::Proto::Kerberos::Pac::NEVER_EXPIRE
        'Never Expires (inf)'
      elsif time.get == 0
        'No Time Set (0)'
      else
        time.to_time.to_s
      end
    end
  end
end
