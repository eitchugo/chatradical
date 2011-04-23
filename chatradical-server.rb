#!/usr/bin/ruby
#
require 'socket'

class Usuario
    attr_reader :id, :timestamp, :sala
    attr_accessor :indice, :nick, :nome

    def initialize(id, nick, nome, descriptor)
        @id = id
        @nick = nick
        @nome = nome
        @descriptor = descriptor
        TimeStamp()
    end

    def TimeStamp
        @timestamp = Time.now
    end

    def EntrarSala(nome)
        @sala = nome
        @indice = 0
        return "RCV_JOINCHN OK " + nome
    end

end

class Sala
    attr_reader :nome, :descricao, :membros
    attr_accessor :nicks

    def initialize(nome, descricao)
        @nome = nome
        @descricao = descricao
        @membros = Array.new()
        @nicks = Array.new()
        @log = Array.new()
    end

    def AdicionarMembro(membro, nick)
        @membros.push(membro)
        @nicks.push(nick)
        @nicks = @nicks.sort()
    end

    def RemoverMembro(membro, nick)
        @membros.delete(membro)
        @nicks.delete(nick)
    end

    def AdicionarLog(linha)
        @log << linha
    end

    def VerLog(tail)
        tamanho = @log.length
        inicio = tamanho - tail

        if inicio < 0
            inicio = 0
        end

        return @log[inicio..tamanho]
    end
end

class ChatRadicalServer

    attr_reader :salas, :connid, :nicks

    def initialize(porta)
        @descriptors = Array.new()
        @connid = 0
        
        @nicks = Hash.new()
        @salas = Hash.new()
        CriaServidor(porta)
    end

    def CriaServidor(porta)
        begin
            puts "server> Iniciando servidor na porta #{porta}..."
            server = TCPServer.open(porta)
            server.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, 1)
            puts "server> Porta aberta."
        rescue
            puts "error> Erro ao tentar abrir a porta!"
        end

        begin
            puts "server> Criando salas padrões..."
            ["default", "Linux", "Ruby", "FIAP"].each do |nome|
                NovaSala(nome)
            end
            puts "server> Salas criadas."
        rescue
            puts "error> Erro ao crias as salas padrões"
        end

        begin
            loop do
                Thread.start(server.accept) do |cliente|
                    @connid += 1
                    connid = @connid          
                    port = cliente.peeraddr[1]
                    host = cliente.peeraddr[2]
                    addr = cliente.peeraddr[3]

                    puts "server> Conexão recebida de #{addr}:#{port}"

                    begin
                        loop do
                            linha = cliente.readline.chomp
                            ClienteConectar(connid,cliente,linha)
                        end
                    rescue
                        puts "server> Desconectado: #{addr}:#{port}"
                    ensure
                        @descriptors.delete(cliente)
                        @salas.each_value do |sala|
                            sala.RemoverMembro(cliente, @nicks[connid])
                        end
                        @nicks.delete(connid)
                        ClienteDesconectar(connid, cliente)
                    end

                end
            end
        rescue Interrupt
           puts "server> Administrador abortou o servidor. Saindo!"
        end 
    end

    def ClienteConectar(connid, cliente, linha)
        connmatch = /^CONN ([a-zA-Z0-9]{1,24}) ([a-zA-Z_-]{1,32})$/i.match linha
        if connmatch
            nick = connmatch[1]
            nome = connmatch[2]

            if @nicks[connid]
                cliente.puts "ERR_CONN Você já está conectado!"
            elsif @nicks.has_value?(nick)
                cliente.puts "ERR_CONN Nick já em uso! Tente outro"
            else
                @nicks[connid] = nick
                @descriptors.push(cliente)

                usuario = Usuario.new(connid, nick, nome, cliente)
                cliente.puts "RCV_CONN OK #{connid}"
                cliente.puts ClienteMotd()
                cliente.puts "RCV_MOTD OK"

                @salas["default"].AdicionarMembro(cliente, usuario.nick)
                cliente.puts usuario.EntrarSala('default')
                msg = "#{usuario.nick} entrou na sala 'default'"
                ChatNotice(usuario, msg)

                ClienteComandos(usuario,cliente)
            end
        elsif linha =~ /^QUIT( |$)/i
            ClienteDesconectar(connid, cliente)
        else
            cliente.puts "ERR_CONN Sintaxe incorreta"
        end
    end

    def ClienteDesconectar(connid, cliente)
        cliente.close
    end

    def ClienteMotd()
        motd = String.new()
        begin
            File.open('motd.txt', 'r') do |arquivo|
                while linha = arquivo.gets
                    motd = motd + linha
                end
            end
            return motd
        rescue
            puts "error> Erro ao ler o arquivo MOTD! Mostrando mensagem meia-boca."
            return "Bem vindo ao ChatRadical!"
        end
    end

    def ClienteComandos(usuario,cliente)
        loop do
            linha = cliente.readline.chomp
            if linha =~ /^CMD_LISTCHN( |$)/i
                lista = ListarSalas()
                cliente.write "RCV_LISTCHN OK "
                lista.each do |sala|
                    cliente.write sala + "|"
                end
                cliente.puts
            elsif linha =~ /^CMD_JOINCHN /i
                match = /^CMD_JOINCHN ([a-zA-Z0-9]{1,24})/i.match linha
                if match
                    sala_atual = usuario.sala
                    if sala_atual
                        msg = "#{usuario.nick} saiu da sala"
                        ChatNotice(usuario, msg)
                        @salas[sala_atual].RemoverMembro(cliente, usuario.nick)
                    end

                    sala = match[1]
                    NovaSala(sala)

                    @salas[sala].AdicionarMembro(cliente, usuario.nick)
                    cliente.puts usuario.EntrarSala(sala)
                    msg = "#{usuario.nick} entrou na sala '#{sala}'"
                    ChatNotice(usuario, msg)
                else
                    cliente.puts "ERR_CMD Nome de sala invalido"
                end
            elsif linha =~ /^CMD_WHOCHN( |$)/i
                sala = usuario.sala
                cliente.write "RCV_WHOCHN OK "
                @salas[sala].nicks.each do |nick|
                    cliente.write "#{nick}|"
                end
                cliente.puts
            elsif linha =~ /^CMD_VLOG /i
                sala = usuario.sala
                match = /^CMD_VLOG ([0-9]{1,2})/.match linha
                if match
                    tail = match[1].to_i
                    log = @salas[sala].VerLog(tail)
                else
                    log = @salas[sala].VerLog(30)
                end

                log.each do |linha_log|
                    cliente.puts "RCV_CHATLOG [LOG] #{linha_log}"
                end
            elsif linha =~ /^CMD_WHOAMI( |$)/i
                cliente.puts "RCV_WHOAMI OK #{usuario.id} #{usuario.nick} #{usuario.nome} #{usuario.sala}"
            elsif linha =~ /^CMD_NICK /i
                match = /^CMD_NICK ([a-zA-Z0-9]{1,24})/i.match linha
                if match
                    if @nicks.has_value?(match[1])
                        cliente.puts "RCV_NICK ERR Nick já em uso"
                    else
                        novo_nick = match[1]
                        @nicks[usuario.id] = novo_nick
                        @salas[usuario.sala].RemoverMembro(cliente, usuario.nick)
                        @salas[usuario.sala].AdicionarMembro(cliente, novo_nick)

                        msg = "#{usuario.nick} trocou de nick para '#{novo_nick}'"
                        ChatNotice(usuario, msg)

                        usuario.nick = novo_nick
                        cliente.puts "RCV_NICK OK"
                    end
                end
            elsif linha =~ /^CMD_CHAT /i
                match = /^CMD_CHAT (.+)/i.match linha
                if match
                    cliente.puts Chat(match[1], usuario)
                else
                    cliente.puts "ERR_CMD Mensagem de chat inválida"
                end
            elsif linha =~ /^QUIT( |$)/i
                msg = "#{usuario.nick} saiu da sala"
                ChatNotice(usuario, msg)
                ClienteDesconectar(usuario.id, cliente)
            else
                cliente.puts "ERR_CMD Comando Invalido"
            end
        end
    end

    def NovaSala(nome)
        unless @salas[nome]
            @salas[nome] = Sala.new(nome, nil)
            puts "server> Nova sala criada: #{nome}"
        end
    end

    def ListarSalas()
        lista = Array.new()
        @salas.each_key do |sala|
            lista = lista + [sala]
        end
        return lista.sort
    end

    def Chat(linha, usuario)
        sala = @salas[usuario.sala]
        msg = Time.now.strftime("[%H:%M:%S] ") + "<#{usuario.nick}> #{linha}"

        sala.AdicionarLog(msg)
        
        membros = sala.membros
        membros.each do |cliente|
            cliente.puts "RCV_CHATMSG #{msg}"
        end

        return "RCV_CHAT OK"
    end

    def ChatNotice(usuario, msg)
        msg = Time.now.strftime("[%H:%M:%S] ") + "*** #{msg}"

        sala = @salas[usuario.sala]
        sala.AdicionarLog(msg)

        membros = sala.membros
        membros.each do |cliente|
            cliente.puts "RCV_CHATMSG #{msg}"
        end

        return "RCV_CHAT OK"
    end

end

server = ChatRadicalServer.new(7000)
