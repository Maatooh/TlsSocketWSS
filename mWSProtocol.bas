Attribute VB_Name = "mWSProtocol"
Option Explicit
Option Compare Text
'==============================================================
'By:       ����Ȼ
'QQ:       2860898817
'E-mail:   ur1986@foxmail.com
'����˼��ͻ���Demo��QȺ�ļ�����:369088586
'��Ŀ����ʱ��: 2015.04.06
'���Ķ�ʱ��: 2017.12.12
'==============================================================
Private Declare Sub CopyMemory Lib "kernel32" Alias "RtlMoveMemory" (Destination As Any, Source As Any, ByVal length As Long)
Public Enum OpcodeType
    opContin = 0    '������ϢƬ��
    opText = 1      '�ı���ϢƬ��
    opBinary = 2    '��������ϢƬ��
                    '3 - 7 �ǿ���֡����
    opClose = 8     '���ӹر�
    opPing = 9      '��������ping
    opPong = 10     '��������pong
                    '11-15 ����֡����
End Enum
Public Type DataFrame
    FIN As Boolean      '0��ʾ���ǵ�ǰ��Ϣ�����һ֡�����滹����Ϣ,1��ʾ���ǵ�ǰ��Ϣ�����һ֡��
    RSV1 As Boolean     '1λ����û���Զ���Э��,����Ϊ0,�������Ͽ�.
    RSV2 As Boolean     '1λ����û���Զ���Э��,����Ϊ0,�������Ͽ�.
    RSV3 As Boolean     '1λ����û���Զ���Э��,����Ϊ0,�������Ͽ�.
    Opcode As OpcodeType    '4λ�����룬������Ч�������ݣ�����յ���һ��δ֪�Ĳ����룬���ӱ���Ͽ�.
    MASK As Boolean     '1λ�����崫��������Ƿ��м�����,���������������MaskingKey
    MaskingKey(3) As Byte   '32λ������
    Payloadlen As Long  '�������ݵĳ���
    DataOffset As Long  '����Դ��ʼλ
End Type

'==============================================================
'���ֲ���,ֻ��һ�����ŵ��ú��� Handshake(requestHeader As String) As Byte()
'==============================================================
Private Const MagicKey = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
Private Const B64_CHAR_DICT = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/="
Public Function Handshake(requestHeader As String) As Byte()
    Dim clientKey As String
    clientKey = getHeaderValue(requestHeader, "Sec-WebSocket-Key:")
    Dim AcceptKey As String
    AcceptKey = getAcceptKey(clientKey)
    Dim response As String
    response = "HTTP/1.1 101 Web Socket Protocol Handshake" & vbCrLf
    response = response & "Upgrade: WebSocket" & vbCrLf
    response = response & "Connection: Upgrade" & vbCrLf
    response = response & "Sec-WebSocket-Accept: " & AcceptKey & vbCrLf
    response = response & "WebSocket-Origin: " & getHeaderValue(requestHeader, "Sec-WebSocket-Origin:") & vbCrLf
    response = response & "WebSocket-Location: " & getHeaderValue(requestHeader, "Host:") & vbCrLf
    'response = response & "WebSocket-Server: VB.Shunshisan" & vbCrLf
    response = response & vbCrLf
    'Debug.Print response
    Handshake = StrConv(response, vbFromUnicode)
End Function
Private Function getHeaderValue(str As String, pname As String) As String
    Dim i As Long, j As Long
    i = InStr(str, pname)
    If i > 0 Then
        j = InStr(i, str, vbCrLf)
        If j > 0 Then
            i = i + Len(pname)
            getHeaderValue = Trim(Mid(str, i, j - i))
        End If
    End If
End Function
Private Function getAcceptKey(key As String) As String
    Dim b() As Byte
    b = mSHA1.SHA1(StrConv(key & "258EAFA5-E914-47DA-95CA-C5AB0DC85B11", vbFromUnicode))
    getAcceptKey = EnBase64(b)
End Function
Private Function EnBase64(str() As Byte) As String
    On Error GoTo over
    Dim buf() As Byte, length As Long, mods As Long
    mods = (UBound(str) + 1) Mod 3
    length = UBound(str) + 1 - mods
    ReDim buf(length / 3 * 4 + IIf(mods <> 0, 4, 0) - 1)
    Dim i As Long
    For i = 0 To length - 1 Step 3
        buf(i / 3 * 4) = (str(i) And &HFC) / &H4
        buf(i / 3 * 4 + 1) = (str(i) And &H3) * &H10 + (str(i + 1) And &HF0) / &H10
        buf(i / 3 * 4 + 2) = (str(i + 1) And &HF) * &H4 + (str(i + 2) And &HC0) / &H40
        buf(i / 3 * 4 + 3) = str(i + 2) And &H3F
    Next
    If mods = 1 Then
        buf(length / 3 * 4) = (str(length) And &HFC) / &H4
        buf(length / 3 * 4 + 1) = (str(length) And &H3) * &H10
        buf(length / 3 * 4 + 2) = 64
        buf(length / 3 * 4 + 3) = 64
    ElseIf mods = 2 Then
        buf(length / 3 * 4) = (str(length) And &HFC) / &H4
        buf(length / 3 * 4 + 1) = (str(length) And &H3) * &H10 + (str(length + 1) And &HF0) / &H10
        buf(length / 3 * 4 + 2) = (str(length + 1) And &HF) * &H4
        buf(length / 3 * 4 + 3) = 64
    End If
    For i = 0 To UBound(buf)
        EnBase64 = EnBase64 + Mid(B64_CHAR_DICT, buf(i) + 1, 1)
    Next
over:
End Function
'==============================================================
'����֡����,����֡�ṹ
'==============================================================
Public Function AnalyzeHeader(byt() As Byte) As DataFrame
    Dim DF As DataFrame
    Dim l(3) As Byte
    DF.FIN = IIf((byt(0) And &H80) = &H80, True, False)
    DF.RSV1 = IIf((byt(0) And &H40) = &H40, True, False)
    DF.RSV2 = IIf((byt(0) And &H20) = &H20, True, False)
    DF.RSV3 = IIf((byt(0) And &H10) = &H10, True, False)
    DF.Opcode = byt(0) And &H7F
    DF.MASK = IIf((byt(1) And &H80) = &H80, True, False)
    Dim plen As Byte
    plen = byt(1) And &H7F
    If plen < 126 Then
        DF.Payloadlen = plen
        If DF.MASK Then
            CopyMemory DF.MaskingKey(0), byt(2), 4
            DF.DataOffset = 6
        Else
            DF.DataOffset = 2
        End If
    ElseIf plen = 126 Then
        l(0) = byt(3)
        l(1) = byt(2)
        CopyMemory DF.Payloadlen, l(0), 4
        If DF.MASK Then
            CopyMemory DF.MaskingKey(0), byt(4), 4
            DF.DataOffset = 8
        Else
            DF.DataOffset = 4
        End If
    ElseIf plen = 127 Then
        '�ⲿ��û��ʲô����Ͳ�д��,��ΪVBû��64λ�����Ϳɹ�ʹ��
        '���ԶԳ����趨Ϊ-1,�Լ����ж�
        If byt(2) <> 0 Or byt(3) <> 0 Or byt(4) <> 0 Or byt(5) <> 0 Then
            '����32λ
            DF.Payloadlen = -1
        Else
            l(0) = byt(9)
            l(1) = byt(8)
            l(2) = byt(7)
            l(3) = byt(6)
            CopyMemory DF.Payloadlen, l(0), 4
            If DF.Payloadlen <= 0 Then
                '�����з���
                DF.Payloadlen = -1
            Else
                If DF.MASK Then
                    CopyMemory DF.MaskingKey(0), byt(10), 4
                    DF.DataOffset = 14
                Else
                    DF.DataOffset = 10
                End If
            End If
        End If
    End If
    AnalyzeHeader = DF
End Function
'==============================================================
'���յ����ݴ���,������ͷ�����
'PickDataV  �����ǳ������ܵĿ���,������ʱ����ֻ��Ϊ�˽���,��һЩ�߼��ж�,������Ҫ�����ݿ���е�������
'PickData   ��׸����...
'==============================================================
Public Sub PickDataV(byt() As Byte, dataType As DataFrame)
    Dim lenLimit As Long
    lenLimit = dataType.DataOffset + dataType.Payloadlen - 1
    If dataType.MASK And lenLimit <= UBound(byt) Then
        Dim i As Long, j As Long
        For i = dataType.DataOffset To lenLimit
            byt(i) = byt(i) Xor dataType.MaskingKey(j)
            j = j + 1
            If j = 4 Then j = 0
        Next i
    End If
End Sub
Public Function PickData(byt() As Byte, dataType As DataFrame) As Byte()
    Dim b() As Byte
    PickDataV byt, dataType
    ReDim b(dataType.Payloadlen - 1)
    CopyMemory b(0), byt(dataType.DataOffset), dataType.Payloadlen
    PickData = b
End Function

'==============================================================
'���͵����ݴ���,�ò���δ��������,ʹ������ķ�ʽ������֤
'Private Sub Command1_Click()
'    Dim str As String, b() As Byte, bs() As Byte
'    Dim DF As DataFrame
'    str = "abc123"
'    Showlog "��װǰ����:" & str
'    b = mWSProtocol.PackMaskString(str):    Showlog "������ֽ�:" & BytesToHex(b)
'    DF = mWSProtocol.AnalyzeHeader(b):      Showlog "�ṹ��ƫ��:" & DF.DataOffset & "  ����:" & DF.Payloadlen
'    bs = mWSProtocol.PickData(b, DF):       Showlog "��ԭ���ֽ�:" & BytesToHex(bs)
'    Showlog "��ԭ������:" & StrConv(bs, vbUnicode)
'End Sub
'==============================================================
'���������ݵ���װ,���ڷ������ͻ��˷���
'--------------------------------------------------------------
Public Function PackString(str As String, Optional dwOpcode As OpcodeType = opText) As Byte()
    Dim b() As Byte
    b = mUTF8.Encoding(str) 'Ĭ��UTF8
    PackString = PackData(b, dwOpcode)
End Function
Public Function PackData(data() As Byte, Optional dwOpcode As OpcodeType = opText) As Byte()
    Dim length As Long
    Dim byt() As Byte
    length = UBound(data) + 1
    
    If length < 126 Then
        ReDim byt(length + 1)
        byt(1) = CByte(length)
        CopyMemory byt(2), data(0), length
    ElseIf length <= 65535 Then
        ReDim byt(length + 3)
        Dim l(1) As Byte
        byt(1) = &H7E
        CopyMemory l(0), length, 2
        byt(2) = l(1)
        byt(3) = l(0)
        CopyMemory byt(4), data(0), length
    'ElseIf length <= 999999999999999# Then
        '��ô����������...
        'VB6Ҳû����ô�������
        '����Ҫ�͸������������д��
    End If
    '------------------------------
    '��������� byt(0) = &H80 Or dwOpcode �У�&H80 ��Ӧ���� DataFrame �ṹ�е�FIN + RSV1 + RSV2 + RSV3
    'FIN �����Ľ����ǣ�ָʾ�������Ϣ�����Ƭ�Σ���һ��Ƭ�ο���Ҳ������Ƭ�Ρ�
    '�����Ҳ��Ǻ���⣬�������Զ���ְ��õ��ɣ���ò�Ʒְ�Ӧ�ò����Լ��ɿصġ�
    '------------------------------
    byt(0) = &H80 Or dwOpcode
    PackData = byt
End Function
'--------------------------------------------------------------
'���������ݵ���װ,��������ͻ��������˷���
'--------------------------------------------------------------
Public Function PackMaskString(str As String, Optional dwOpcode As OpcodeType = opText) As Byte()
    Dim b() As Byte
    b = mUTF8.Encoding(str) 'Ĭ��UTF8
    PackMaskString = PackMaskData(b, dwOpcode)
End Function
Public Function PackMaskData(data() As Byte, Optional dwOpcode As OpcodeType = opText) As Byte()
    '��Դ���������봦��
    Dim mKey(3) As Byte
    mKey(0) = 108: mKey(1) = 188: mKey(2) = 98: mKey(3) = 208 '����,��Ҳ�����Լ�����
    Dim i As Long, j As Long
    For i = 0 To UBound(data)
        data(i) = data(i) Xor mKey(j)
        j = j + 1
        If j = 4 Then j = 0
    Next i
    '��װ,��������������װPackData()������ͬ
    Dim length As Long
    Dim byt() As Byte
    length = UBound(data) + 1
    If length < 126 Then
        ReDim byt(length + 5)
        byt(0) = &H80 Or dwOpcode '֡����
        byt(1) = (CByte(length) Or &H80)
        CopyMemory byt(2), mKey(0), 4
        CopyMemory byt(6), data(0), length
    ElseIf length <= 65535 Then
        ReDim byt(length + 7)
        Dim l(1) As Byte
        byt(0) = &H80 Or dwOpcode '&H81 'ͬ��ע��
        byt(1) = &HFE '�̶� ����λ+126
        CopyMemory l(0), length, 2
        byt(2) = l(1)
        byt(3) = l(0)
        CopyMemory byt(4), mKey(0), 4
        CopyMemory byt(8), data(0), length
    'ElseIf length <= 999999999999999# Then
        '��ô����������...����Ҫ�͸������������д��
    End If
    PackMaskData = byt
End Function
'==============================================================
'����֡���,Ping��Pong��Close ���ڷ������ͻ��˷���δ��������ź�
'���õ�0����,��ʵ�ǿ��԰������ݵ�,���Ǹ������ݿͻ��˴������鷳��

'ʹ�þ���: Winsock1.SendData mWSProtocol.PongFrame()

'* ����и�����Ϣ������,Ҳ������PackString��PackData,��ѡ����ָ��OpcodeType
'* Э��涨,�������ַ�����Ϣ,��Ȼ�����������,�ͻ��˷�������,����˷��Ͳ�����
'==============================================================
Public Function PingFrame(Optional msg As String = "", Optional UseMask As Boolean = False) As Byte()
    Dim b(1) As Byte
    b(0) = &H89
    b(1) = &H0
    PingFrame = b
    '����һ������"Hello"��Ping�ź�: 0x89 0x05 0x48 0x65 0x6c 0x6c 0x6f
End Function
Public Function PongFrame(Optional msg As String = "", Optional UseMask As Boolean = False) As Byte()
    Dim b(1) As Byte
    b(0) = &H8A
    b(1) = &H0
    PongFrame = b
    '����һ������"Hello"��Pong�ź�: 0x8A 0x05 0x48 0x65 0x6c 0x6c 0x6f
End Function
Public Function CloseFrame(Optional msg As String = "", Optional UseMask As Boolean = False) As Byte()
    Dim b(1) As Byte
    b(0) = &H88
    b(1) = &H0
    CloseFrame = b
    '����һ������"Close"��Pong�ź�: 0x8A 0x05 0x43 0x6c 0x6f 0x73 0x65
End Function
