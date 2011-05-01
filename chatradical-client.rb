#!/usr/bin/ruby
# 
require 'socket'

class ChatRadicalClient
    def initialize(hostname, port)
        begin
            puts "client> Conectando-se ao servidor #{hostname}:#{port}..."
            @server = TCPSocket.open(hostname, port)
            puts "client> Conectado."
            Conectar()
            Listener()
            
        rescue EOFError
            puts "client> Conexão finalizada."
        rescue Interrupt
            puts "client> Usuário abortou o programa. Saindo..."
        rescue
            puts "error> Não foi possível conectar-se ao servidor!"
            raise
        ensure
            @server.close
        end
    end

    def Conectar()
 
        loop do
            print "Entre com seu nick: "
            nick = STDIN.gets.chomp
            print "Entre com seu nome: "
            nome = STDIN.gets.chomp

            @server.puts "CONN #{nick} #{nome}"
            resposta = @server.readline.chomp
            if resposta =~ /^ERR_CONN /
                match = /^ERR_CONN (.*)/.match resposta
                if match
                    puts "ERRO: #{match[1]}"
                end
            elsif resposta =~ /^RCV_CONN OK /
                match = /^RCV_CONN OK ([0-9]+)$/.match resposta
                if match
                    puts "Conectado! Sua conexão é de número #{match[1]}."
                    while motd = @server.readline.chomp
                        if motd =~ /^RCV_MOTD OK$/
                            break
                        else
                            puts(motd)
                        end
                    end
                    break
                end
            end
        end
    end

    def Listener()

        # Thread do input do usuario
        Thread.new do
           loop do
               usercmd = STDIN.gets
               UserCMD(usercmd)
           end
        end

        # Infelizmente no Windows o select so atua em sockets, entao
        # STDIN fica na thread anterior
        loop do
            res = select([@server], nil, nil, nil)
            if res
                for inp in res[0]
                    if inp == @server
                        linha = @server.readline.chomp
                        RecebimentoDoServer(linha)
                    end
                end
            end
        end
    end

    def RecebimentoDoServer(linha)
        if linha =~ /^RCV_JOINCHN /
            match = /^RCV_JOINCHN (ERR (.*)|OK ([\w]+))$/.match linha
            if match
                if match[1] =~ /^ERR /
                    puts "error> #{match[2]}"
                else
                    puts "client> Mudando para a sala '#{match[3]}'"
                end
            end
        elsif linha =~ /^RCV_LISTCHN OK /
            match = /^RCV_LISTCHN OK (.+)/.match linha
            if match
                puts "client> Salas disponíveis:"
                match[1].split('|').each do |sala|
                    puts "client>    - #{sala}"
                end
            end
        elsif linha =~ /^RCV_WHOCHN OK /
            match = /^RCV_WHOCHN OK ([a-zA-Z0-9\|]+)/.match linha
            if match
                puts "client> Usuarios na sala:"
                match[1].split('|').each do |membro|
                    puts "client>    - #{membro}"
                end
            end
        elsif linha =~ /^RCV_INFOCHN OK /
            match = /^RCV_INFOCHN OK ([a-zA-Z0-9]{1,24}) (.+)/.match linha
            if match
                puts "client> Você está no canal #{match[1]} - #{match[2]}"
            end
        elsif linha =~ /^RCV_NICK /
            match = /^RCV_NICK (ERR (.*)|OK)/.match linha
            if match
                if match[1] =~ /^ERR /
                    puts "error> #{match[2]}"
                else
                    puts "client> Nick mudado."
                end
            end
         elsif linha =~ /^RCV_PVT /
            match = /^RCV_PVT (ERR (.*)|OK)/.match linha
            if match
                if match[1] =~ /^ERR /
                    puts "error> #{match[2]}"
                else
                    puts "client> Mensagem enviada."
                end
            end
        elsif linha =~ /^RCV_CHATLOG /
            match = /^RCV_CHATLOG (.+)/.match linha
            if match
                puts match[1]
            end
        elsif linha =~ /^RCV_CHATMSG /
            match = /^RCV_CHATMSG (.+)/.match linha
            if match
                puts match[1]
            end
        end
    end

    def UserCMD(linha)
        if linha =~ /^\/list( |$)/i
            ListarSalas()
        elsif linha =~ /^\/who( |$)/i
            ListarMembros()
        elsif linha =~ /^\/join /i
            match = /^\/join ([a-zA-Z0-9]{1,24})( (.+))?/.match linha
            if match
                EntrarSala(match[1], match[3])
            end
        elsif linha =~ /^\/info( |$)/i
            InfoSala()
        elsif linha =~ /^\/nick /i
            match = /^\/nick ([a-zA-Z0-9]{1,24})$/.match linha
            if match
                MudarNick(match[1])
            end
        elsif linha =~ /^\/msg /i
            match = /^\/msg ([a-zA-Z0-9]{1,24}) (.+)/.match linha
            if match
                EnviarPVT(match[1], match[2])
            end
        elsif linha =~ /^\/log( |$)/i
            match = /^\/log ([0-9]{1,2})/.match linha
            if match
                VerLog(match[1])
            else
                VerLog()
            end
        elsif linha =~ /^\/quit( |$)/i
            Desconectar()
        elsif linha =~ /^\//i
            puts "error> Comando inválido!"
        else
            @server.puts "CMD_CHAT #{linha}"
        end
    end

    def ListarSalas
        @server.puts "CMD_LISTCHN"
    end

    def ListarMembros
        @server.puts "CMD_WHOCHN"
    end

    def InfoSala
        @server.puts "CMD_INFOCHN"
    end

    def EntrarSala(nome, descricao)
        @server.puts "CMD_JOINCHN #{nome} #{descricao}"
    end

    def VerLog(tail=nil)
        @server.puts "CMD_VLOG #{tail}"
    end

    def MudarNick(nick)
        @server.puts "CMD_NICK #{nick}"
    end

    def EnviarPVT(nick, msg)
        @server.puts "CMD_PVT #{nick} #{msg}"
    end

    def Desconectar
        puts "client> Saindo..."
        @server.puts "QUIT"
    end
 
end

client = ChatRadicalClient.new("localhost", "7000")
